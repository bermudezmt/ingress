local new_timer = ngx.timer.at
local _M = {}

local function interval_thread(premature, interval, all_workers, func, ...)
  if premature or ngx.worker.exiting() then return end
  if all_workers or ngx.worker.id() == 0 then
    func(...)
    new_timer(interval, interval_thread, interval, all_workers, func, ...)
  end
end

function _M.execute_at_interval(interval, all_workers, func, ...)
  new_timer(0, interval_thread, interval, all_workers, func, ...)
end

return _M
