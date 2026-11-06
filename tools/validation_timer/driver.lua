-- Development-only timer measurement in a separate driver. No network or persistence.
local timer, generation = nil, 0
local INTERVAL, DURATION = 100, 15000

local function cancel()
  generation = generation + 1
  if timer then
    timer:Cancel()
    timer = nil
  end
end

local function update(name, value)
  C4:UpdateProperty(name, tostring(value))
end

function OnDriverInit()
  cancel()
  update("Probe Status", "Idle")
end

function ExecuteCommand(command, params)
  if command == "LUA_ACTION" then
    command = params and params.ACTION
  end
  if command == "Stop_Probe" then
    cancel()
    update("Probe Status", "Stopped")
    return
  end
  if command ~= "Start_Probe" then
    return
  end
  cancel()
  local run = generation
  local started, previous = C4:GetTime(), nil
  previous = started
  local count, maximum, skipped = 0, 0, 0
  update("Probe Status", "Running for 15 seconds")
  update("Started (UTC)", os.date("!%Y-%m-%d %H:%M:%S UTC", math.floor(started / 1000)))
  update("Finished (UTC)", "")
  for _, name in ipairs({
    "Callback Count",
    "Maximum Gap (ms)",
    "Maximum Extra Delay (ms)",
    "Skipped Intervals",
    "Elapsed (ms)",
  }) do
    update(name, 0)
  end
  print("Schlage timer probe started: 100 ms interval, 15 seconds. Run account Sign In now.")
  timer = C4:SetTimer(INTERVAL, function(_, missed)
    if run ~= generation then
      return
    end
    local now = C4:GetTime()
    if now < previous then
      cancel()
      update("Probe Status", "Invalid measurement: clock moved backward")
      return
    end
    maximum = math.max(maximum, now - previous)
    previous = now
    count = count + 1
    skipped = skipped + (tonumber(missed) or 0)
    local elapsed = now - started
    if elapsed >= DURATION then
      cancel()
      update("Callback Count", count)
      update("Maximum Gap (ms)", maximum)
      update("Maximum Extra Delay (ms)", math.max(0, maximum - INTERVAL))
      update("Skipped Intervals", skipped)
      update("Elapsed (ms)", elapsed)
      update("Finished (UTC)", os.date("!%Y-%m-%d %H:%M:%S UTC", math.floor(now / 1000)))
      update("Probe Status", "Complete")
      print(
        string.format(
          "Schlage timer probe complete: callbacks=%d; max_gap_ms=%d; extra_delay_ms=%d; skipped=%d; elapsed_ms=%d",
          count,
          maximum,
          math.max(0, maximum - INTERVAL),
          skipped,
          elapsed
        )
      )
    end
  end, true)
end

function OnDriverDestroyed()
  cancel()
end
