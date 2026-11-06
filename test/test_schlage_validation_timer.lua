require("c4_shim")
local T = require("testlib")
local now, scheduled, properties = 1000000, {}, {}
function C4:GetTime()
  return now
end
function C4:UpdateProperty(name, value)
  properties[name] = value
end
function C4:SetTimer(interval, callback, repeating)
  local handle = { interval = interval, callback = callback, repeating = repeating, cancelled = false }
  function handle:Cancel()
    self.cancelled = true
  end
  scheduled[#scheduled + 1] = handle
  return handle
end
local ok, err = T.capture(function()
  dofile("tools/validation_timer/driver.lua")
  OnDriverInit()
  T.eq("no timer scheduled during init", #scheduled, 0)
  ExecuteCommand("LUA_ACTION", { ACTION = "Start_Probe" })
  local timer = scheduled[#scheduled]
  T.eq("100 ms repeating interval", timer.interval, 100)
  T.truthy("uses a repeating timer", timer.repeating)
  now = now + 115
  timer.callback(timer, 0)
  for _ = 1, 149 do
    now = now + 100
    timer.callback(timer, 0)
  end
  T.eq("measurement completes", properties["Probe Status"], "Complete")
  T.eq("callbacks measured", properties["Callback Count"], "150")
  T.eq("jitter measured", properties["Maximum Gap (ms)"], "115")
  T.eq("extra delay measured", properties["Maximum Extra Delay (ms)"], "15")
  T.eq("duration measured", properties["Elapsed (ms)"], "15015")
  T.truthy("completed timer cancelled", timer.cancelled)
  ExecuteCommand("LUA_ACTION", { ACTION = "Start_Probe" })
  timer = scheduled[#scheduled]
  now = now + 450
  timer.callback(timer, 3)
  for _ = 1, 146 do
    now = now + 100
    timer.callback(timer, 0)
  end
  T.eq("stall recorded", properties["Maximum Gap (ms)"], "450")
  T.eq("missed intervals recorded", properties["Skipped Intervals"], "3")
  ExecuteCommand("LUA_ACTION", { ACTION = "Start_Probe" })
  timer = scheduled[#scheduled]
  ExecuteCommand("LUA_ACTION", { ACTION = "Stop_Probe" })
  now = now + 20000
  timer.callback(timer, 10)
  T.eq("cancelled callback cannot publish a result", properties["Probe Status"], "Stopped")
  ExecuteCommand("LUA_ACTION", { ACTION = "Start_Probe" })
  timer = scheduled[#scheduled]
  now = now - 1
  timer.callback(timer, 0)
  T.eq(
    "clock discontinuity invalidates sample",
    properties["Probe Status"],
    "Invalid measurement: clock moved backward"
  )
  ExecuteCommand("LUA_ACTION", { ACTION = "Start_Probe" })
  timer = scheduled[#scheduled]
  OnDriverDestroyed()
  T.truthy("destruction cancels timer", timer.cancelled)
end)
T.truthy("probe lifecycle runs", ok, err)
T.finish()
