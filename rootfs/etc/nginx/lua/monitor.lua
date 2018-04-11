local statsd = require("statsd")
local ngx_internal = require("ngx.internals")

local timer = require("util.timer")
local worker_pid = ngx.worker.pid

local STATSD_USED_CONNECTIONS = "nginx.worker.used_connections"
local STATSD_FREE_CONNECTIONS = "nginx.worker.free_connections"
local STATSD_MAX_CONNECTIONS = "nginx.worker.max_connections"
local STATSD_USED_CONNECTIONS_PERCENTAGE = "nginx.worker.used_connections_percentage"

local STATSD_MAX_PENDING_TIMERS = "nginx.worker.max_pending_timers"
local STATSD_PENDING_TIMERS = "nginx.worker.pending_timers"
local STATSD_PENDING_TIMERS_PERCENTAGE = "nginx.worker.pending_timers_percentage"

local STATSD_MAX_RUNNING_TIMERS = "nginx.worker.max_running_timers"
local STATSD_RUNNING_TIMERS = "nginx.worker.running_timers"
local STATSD_RUNNING_TIMERS_PERCENTAGE = "nginx.worker.running_timers_percentage"

local STATSD_MONITOR_TIME = "nginx.worker.monitor_time"

local MONITOR_INTERVAL = 1.0

local _M = {}

local function log_to_statsd()
  local used_connections = ngx_internal.used_connections()
  local max_connections = ngx_internal.max_connections()
  local free_connections = ngx_internal.free_connections()
  local used_connections_percentage = (used_connections/max_connections)*100

  statsd.gauge(STATSD_USED_CONNECTIONS, used_connections, { pid = worker_pid() })
  statsd.gauge(STATSD_FREE_CONNECTIONS, free_connections, { pid = worker_pid() })
  statsd.gauge(STATSD_MAX_CONNECTIONS, max_connections,  { pid = worker_pid() })
  statsd.gauge(STATSD_USED_CONNECTIONS_PERCENTAGE, used_connections_percentage,  { pid = worker_pid() })

  local pending_timers = ngx_internal.pending_timers()
  local max_pending_timers = ngx_internal.max_pending_timers()
  local pending_timers_percentage = (pending_timers/max_pending_timers)*100

  statsd.gauge(STATSD_PENDING_TIMERS,  pending_timers,  { pid = worker_pid() })
  statsd.gauge(STATSD_MAX_PENDING_TIMERS,  max_pending_timers,  { pid = worker_pid() })
  statsd.gauge(STATSD_PENDING_TIMERS_PERCENTAGE,  pending_timers_percentage,  { pid = worker_pid() })

  local running_timers = ngx_internal.running_timers()
  local max_running_timers = ngx_internal.max_running_timers()
  local running_timers_percentage = (running_timers/max_running_timers)*100

  statsd.gauge(STATSD_RUNNING_TIMERS, running_timers,  { pid = worker_pid() })
  statsd.gauge(STATSD_MAX_RUNNING_TIMERS, max_running_timers,  { pid = worker_pid() })
  statsd.gauge(STATSD_RUNNING_TIMERS_PERCENTAGE, running_timers_percentage,  { pid = worker_pid() })
end

local function report_status()
  statsd.measure(STATSD_MONITOR_TIME, log_to_statsd)
end

function _M.init_worker()
  timer.execute_at_interval(MONITOR_INTERVAL, false, report_status)
  return true, nil
end

return _M
