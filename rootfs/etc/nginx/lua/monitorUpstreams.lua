local ok, upstream = pcall(require, "ngx.upstream")
if not ok then
  ngx.log(ngx.ERR, "require(upstream) failed, not starting monitor_upstreams: " .. tostring(upstream))
  return {}
end

local statsd = require("statsd")
local healthcheck = require("resty.upstream.healthcheck")

local timer = require("util.timer")
local statsd_gauge = statsd.gauge

local STATSD_HEALTH_CHECK_FAILS = "nginx.upstream.health_checks.fails"
local STATSD_HEALTH_CHECK_PASSES = "nginx.upstream.health_checks.passes"
local STATSD_HEALTH_CHECKS_CHECKED = "nginx.upstream.health_checks.checked"
local STATSD_HEALTH_CHECKS_UNHEALTHY = "nginx.upstream.health_checks.unhealthy"
local STATSD_HEALTH_CHECKS_PERCENT = "nginx.upstream.health_checks.healthy_percent"
local STATSD_MONITOR_UPSTREAMS_TIME = "nginx.worker.monitor_upstreams_time"

local MONITOR_INTERVAL = 1.0

local _M = {}

local function send_healthcheck_status(upstream_name, peers)
  for i = 1, #peers do
    local peer = peers[i]

    if peer.unhealthy ~= nil then
      local tags = {
        upstream = upstream_name,
        peer = peer.name,
      }

      if peer.unhealthy then
        statsd_gauge(STATSD_HEALTH_CHECK_FAILS, peer.checks_fail, tags)
        statsd_gauge(STATSD_HEALTH_CHECK_PASSES, 0, tags)
      else
        statsd_gauge(STATSD_HEALTH_CHECK_PASSES, peer.checks_ok, tags)
        statsd_gauge(STATSD_HEALTH_CHECK_FAILS, 0, tags)
      end
    end
  end
end

local function peers_healthcheck_metrics(peers)
  local unhealthy = 0
  local checked = 0

  for i = 1, #peers do
    local peer = peers[i]

    if peer.unhealthy ~= nil then
      checked = checked + 1
      if peer.unhealthy then
        unhealthy = unhealthy + 1
      end
    end
  end

  return unhealthy, checked
end

local function healthcheck_metrics(status_table_for_upstream)
  local unhealthy_p, checked_p = peers_healthcheck_metrics(status_table_for_upstream.primary_peers)
  local unhealthy_b, checked_b = peers_healthcheck_metrics(status_table_for_upstream.backup_peers)
  return unhealthy_p + unhealthy_b, checked_p + checked_b
end

local function healthy_percent(ht_status_table)
  local total_unhealthy = 0
  local total_checked = 0

  for _, st in pairs(ht_status_table) do
    local unhealthy, checked = healthcheck_metrics(st)

    total_unhealthy = total_unhealthy + unhealthy
    total_checked = total_checked + checked
  end

  if total_checked == 0 then
    return 100
  else
    local healthy_ratio = 1 - total_unhealthy / total_checked
    return math.floor(healthy_ratio * 100 + 0.5)
  end
end

function _M.healthcheck_status()
  local ht_status_table, err = healthcheck.status_table("healthcheck")
  if err then
    ngx.log(ngx.ERR, "healthcheck.status_table failed: " .. tostring(err))
    return nil, nil
  end
  local percent = healthy_percent(ht_status_table)
  return ht_status_table, percent
end

local function log_to_statsd()
  local ht_status_table, err = healthcheck.status_table("healthcheck")
  if err then
    ngx.log(ngx.ERR, "healthcheck.status_table failed, not recording stats: " .. tostring(err))
    return
  end

  for upstream_name, st in pairs(ht_status_table) do
    send_healthcheck_status(upstream_name, st.primary_peers)
    send_healthcheck_status(upstream_name, st.backup_peers)

    local unhealthy, checked = healthcheck_metrics(st)
    statsd_gauge(STATSD_HEALTH_CHECKS_UNHEALTHY, unhealthy, { upstream = upstream_name })

    statsd_gauge(STATSD_HEALTH_CHECKS_CHECKED, checked, { upstream = upstream_name })
  end

  statsd_gauge(STATSD_HEALTH_CHECKS_PERCENT, healthy_percent(ht_status_table))
end

local function report_status()
  statsd.measure(STATSD_MONITOR_UPSTREAMS_TIME, log_to_statsd)
end

function _M.init_worker()
  timer.execute_at_interval(MONITOR_INTERVAL, false, report_status)
  return true, nil
end

function _M.healthy_percent()
  local ht_status_table, err = healthcheck.status_table("healthcheck")
  if err then
    ngx.log(ngx.ERR, "healthcheck.status_table failed, healthy_percent assumed 100: " .. tostring(err))
    return 100
  end

  return healthy_percent(ht_status_table)
end

function _M.healthcheck_metrics_by_upstream()
  local ht_status_table, err = healthcheck.status_table("healthcheck")
  if err then
    ngx.log(ngx.ERR, "healthcheck.status_table failed: " .. tostring(err))
    return nil
  end

  local metrics_by_upstream = {}

  for upstream_name, st in pairs(ht_status_table) do
    local unhealthy, checked = healthcheck_metrics(st)

    metrics_by_upstream[upstream_name] = {
      unhealthy = unhealthy,
      checked = checked,
    }
  end

  return metrics_by_upstream
end

_M.force_flush_metrics = log_to_statsd

return _M
