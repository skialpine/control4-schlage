local T = require("testlib")
local Poller = require("schlage.poller")
local retry_after = require("schlage.retry_after")
local now, events, requests, pending, stale, latest = 0, {}, 0, nil, 0, nil
local function schedule(delay, callback)
  local event = { at = now + delay, callback = callback }
  events[#events + 1] = event
  return {
    cancel = function()
      event.cancelled = true
    end,
  }
end
local function advance(target)
  while true do
    local index, earliest
    for i, event in ipairs(events) do
      if not event.cancelled and event.at <= target and (not earliest or event.at < earliest.at) then
        index, earliest = i, event
      end
    end
    if not index then
      break
    end
    table.remove(events, index)
    now = earliest.at
    earliest.callback()
  end
  now = target
end
local client = {
  discover = function(_, callback)
    requests = requests + 1
    pending = callback
  end,
  cancel = function() end,
}
local poller = Poller.new({
  client = client,
  schedule = schedule,
  now = function()
    return now
  end,
  jitter = function(low, high)
    T.truthy("retry jitter stays bounded", low == 5 and high >= 5 and high <= 300)
    return high
  end,
  on_stale = function()
    stale = stale + 1
  end,
  on_result = function(devices, err)
    latest = { devices, err }
  end,
})

T.section("Default and configured interval, shared manual/scheduled read")
T.eq("30 second default", poller.interval, 30)
poller:set_interval(1)
T.eq("15 second minimum", poller.interval, 15)
poller:set_interval("invalid")
T.eq("invalid uses default", poller.interval, 30)
poller:start()
local joined = 0
poller:refresh(function()
  joined = joined + 1
end)
advance(90)
T.eq("no overlapping scheduled read during slow request", requests, 1)
pending({ { id = "one" } })
T.eq("manual waiter shares response", joined, 1)
T.truthy("successful read is fresh", poller:fresh())
advance(119)
T.eq("default interval not early", requests, 1)
advance(120)
T.eq("next poll at interval", requests, 2)
pending(nil, { category = "transport_error" })
T.eq("retrieval failure is not an empty listing", latest[1], nil)
T.eq("failure does not immediately age fresh data", stale, 0)
advance(130)
T.eq("bounded first retry", requests, 3)
pending(nil, { category = "transient_error" })
advance(150)
pending(nil, { category = "transient_error" })
advance(190)
pending(nil, { category = "transient_error" })
advance(210)
T.eq("stale at 120 seconds since last success", stale, 1)
T.falsy("stale data unavailable", poller:fresh())

T.section("Retry-After blocks all cloud-request eligibility, survives long delay")
advance(270)
pending(nil, { category = "rate_limited", retry_after = 600 })
local before = requests
poller:refresh(function(_, err)
  T.eq("manual refresh reports cooldown", err.category, "rate_limited")
end)
T.falsy("writes/readbacks share the cooldown gate", poller:can_request())
advance(869)
T.eq("no request during server delay", requests, before)
advance(870)
T.eq("request resumes after server delay", requests, before + 1)
pending({})
T.eq("valid empty account succeeds", latest[1], {})
T.truthy("successful read restores freshness", poller:fresh())
poller:cooldown({ category = "rate_limited" })
T.eq("missing header fallback is 60 seconds", poller.blocked_until, now + 60)
poller:stop()
local late = pending
late({ { id = "obsolete" } })
T.falsy("stop ignores late callbacks", poller:fresh())
before = requests
advance(2000)
T.eq("all timers cancelled on stop", requests, before)

T.section("HTTP-date formats and numeric Retry-After use UTC")
local epoch = 784111777 -- Sun, 06 Nov 1994 08:49:37 GMT
for _, value in ipairs({ "Sun, 06 Nov 1994 08:49:37 GMT", "Sunday, 06-Nov-94 08:49:37 GMT", "Sun Nov  6 08:49:37 1994" }) do
  T.eq("HTTP-date delay independent of local timezone", retry_after(value, epoch - 73), 73)
  T.eq("past HTTP-date is immediately eligible", retry_after(value, epoch + 1), 0)
end
T.eq("numeric delay", retry_after(" 73 ", epoch), 73)
T.eq("zero delay", retry_after("0", epoch), 0)
for _, value in ipairs({
  "-1",
  "1.5",
  "1e3",
  "infinity",
  "Sun, 31 Feb 1994 08:49:37 GMT",
  "Mon, 06 Nov 1994 08:49:37 GMT",
  "Sun, 06 Nov 1994 25:49:37 GMT",
  "",
}) do
  T.eq("invalid header uses caller fallback", retry_after(value, epoch), nil)
end
T.finish()
