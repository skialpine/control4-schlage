local T = require("testlib")
local Alert = require("schlage.battery_alert")
-- UTC midnight 2026-11-06; injected controller zone is seven hours behind.
local midnight = 1793923200
local now, offset = midnight + 15 * 3600 + 59 * 60, -7 * 3600
local stored, writes, events, message, status, last = {}, 0, 0
local store = {}
function store:get(_, default, encrypted)
  T.truthy("identity ledger is read encrypted", encrypted)
  return stored.records or default
end
function store:set(_, records, encrypted)
  T.truthy("identity ledger is written encrypted", encrypted)
  stored.records = records
  writes = writes + 1
end
local function make()
  return Alert.new({
    persist = store,
    now = function()
      return now
    end,
    date = function(format, when)
      return os.date("!" .. format, when + offset)
    end,
    message = function(value)
      message = value
    end,
    status = function(value)
      status = value
    end,
    last = function(value)
      last = value
    end,
    fire = function()
      T.truthy(
        "message is available before Composer programming runs",
        message and message:find("Low battery:", 1, true)
      )
      T.truthy("daily marker is durable before event dispatch", message:find("TEST:", 1, true) or writes > 0)
      events = events + 1
    end,
  })
end
local a, b = { id = "a", scope = "account" }, { id = "b", scope = "account" }
local function state(extra)
  local s =
    { name = "Front Door", online = true, supported = true, updated_at = now, battery = 20, low_battery = false }
  for k, v in pairs(extra or {}) do
    s[k] = v
  end
  return s
end
local alert = make()
alert:configure({})
T.section("Disabled by default; local time and threshold are configurable")
T.falsy("new option sends nothing until enabled", alert:update(state(), a))
T.eq("disabled status", status, "Disabled")
alert:configure({ enabled = true })
T.falsy("08:59 local is before the default reminder time", alert:update(state(), a))
now = now + 60
T.truthy("threshold equality qualifies at 09:00 local", alert:update(state(), a))
T.eq("first daily event", events, 1)
T.contains("message identifies selected lock and percentage", message, "Front Door (20%)")
T.excludes("public message omits account scope", message, "account")
T.neq("last alert local time is presented", last, "Never")
for _ = 1, 10 do
  alert:update(state(), a)
end
T.eq("polls do not repeat the alert or rewrite the ledger", { events, writes }, { 1, 1 })

T.section("Reload, same-day settings changes and battery flapping do not reset allowance")
alert = make()
alert:configure({ enabled = true, at = "08:00", threshold = "30" })
alert:update(state(), a)
T.eq("restart does not repeat", events, 1)
alert:update(state({ battery = 100 }), a)
alert:update(state({ battery = 5 }), a)
alert:configure({ enabled = false })
alert:update(state(), a)
alert:configure({ enabled = true })
alert:update(state(), a)
T.eq("recovery then low and off/on do not repeat that date", events, 1)
alert:update(state(), b)
T.eq("another selected physical lock has its own allowance", events, 2)
alert:update(state(), a)
T.eq("switching back does not repeat", events, 2)
alert:update(state(), { id = "a", scope = "other-account" })
T.eq("separate account identity is independent", events, 3)

T.section("Fresh-state gates; next local day; outage has no backlog")
now = now + 86400
local before = events
for _, extra in ipairs({
  { online = false },
  { supported = false },
  { updated_at = now - 121 },
  { updated_at = now + 1 },
  { updated_at = 0 / 0 },
  { battery = 21 },
}) do
  alert:update(state(extra), a)
end
local unknown = state()
unknown.battery, unknown.low_battery = nil, nil
alert:update(unknown, a)
T.eq("unavailable, missing, invalid, normal and stale readings do not alert", events, before)
T.truthy("fresh next-day observation alerts", alert:update(state(), a))
T.eq("one event on next local date", events, before + 1)
now = now + 5 * 86400
alert:update(state({ online = false }), a)
alert:update(state(), a)
T.eq("reconnection emits only current date, not five missed reminders", events, before + 2)
alert:update(state(), a)
T.eq("reconnection repeats are suppressed", events, before + 2)

T.section("Schlage low flag is independent; invalid settings fail visibly")
now = now + 86400
T.truthy(
  "Schlage low flag qualifies even above percentage threshold",
  alert:update(state({ battery = 80, low_battery = true }), a)
)
now = now + 86400
local coarse = state({ low_battery = true })
coarse.battery = nil
T.truthy("Schlage low flag qualifies with no percentage", alert:update(coarse, a))
now = now + 86400
before = events
for _, settings in ipairs({
  { at = "24:00" },
  { at = "12:60" },
  { at = "9:00" },
  { at = "bad" },
  { at = 42 },
  { threshold = "bad" },
  { threshold = -1 },
  { threshold = 101 },
  { threshold = math.huge },
}) do
  settings.enabled = true
  alert:configure(settings)
  T.falsy("invalid settings cannot emit", alert:update(state(), a))
  T.contains("invalid settings show useful feedback", status, "Invalid")
end
T.eq("invalid configuration causes no alerts", events, before)
alert:configure({ enabled = true, at = "10:00", threshold = 0 })
T.falsy("valid later time waits", alert:update(state({ battery = 0 }), a))
now = now + 3600
T.truthy("zero battery is a supplied percentage", alert:update(state({ battery = 0 }), a))

T.section("Clock changes and test action")
before = events
now = now - 86400
alert:update(state({ battery = 0 }), a)
T.eq("clock rollback cannot repeat an older date", events, before)
offset = offset + 3600
alert:update(state({ battery = 0 }), a)
T.eq("daylight-saving clock shift does not repeat", events, before)
now = now + 2 * 86400
alert:configure({ enabled = false })
alert:update(state({ battery = 100, online = false }), a)
local previous_writes = writes
T.truthy("explicit test runs while disabled and offline", alert:check(true))
T.contains("test message is labeled", message, "TEST:")
T.eq("test does not consume daily allowance", writes, previous_writes)
T.eq("test does not change battery reading", alert.state.battery, 100)
alert:configure({ enabled = true })
T.truthy("real qualifying observation still alerts after test", alert:update(state(), a))
alert:stop()
T.falsy("stopped instance cannot send even an explicit test", alert:check(true))

T.section("Reentrant programming and malformed persistence")
alert = make()
alert:configure({ enabled = true })
now = now + 86400
local saved_fire = alert.fire
alert.fire = function()
  alert:check()
  saved_fire()
end
before = events
alert:update(state(), a)
T.eq("programming reentry cannot create a second event", events, before + 1)
alert.records["7:accounta"] = { at = 1e300, day = "invalid" }
T.truthy(
  "malformed saved timestamp cannot crash alert evaluation",
  pcall(function()
    alert:update(state(), a)
  end)
)

T.section("Automatic push is independent, once daily, and never blindly retried")
local pushes, ready = {}, false
alert = make()
alert.push_ready = function()
  return ready
end
alert.push = function(_, value)
  pushes[#pushes + 1] = value
  return true
end
alert:configure({ enabled = true })
now = now + 86400
alert:update(state(), a)
before = events
T.eq("automatic push defaults Off while Composer event is available", #pushes, 0)
alert:configure({ enabled = true, push_enabled = true })
alert:update(state(), a)
T.eq("missing push service cannot consume a daily push attempt", #pushes, 0)
T.eq("enabling push does not repeat Composer event", events, before)
ready = true
alert:update(state(), a)
T.eq("push enabled after daily event can still submit that date", #pushes, 1)
T.contains("push contains the lock name", pushes[1], "Front Door")
alert:configure({ enabled = true, push_enabled = false })
alert:update(state(), a)
alert:configure({ enabled = true, push_enabled = true })
alert:update(state(), a)
T.eq("Off/On cannot send a second push for that date", #pushes, 1)
now = now + 86400
alert.push = function()
  error("synthetic submission uncertainty")
end
alert:update(state(), a)
T.eq("uncertain submission is reported without propagating raw error", status, "Push submission failed")
local attempted = writes
alert:update(state(), a)
T.eq("uncertain push attempt is not replayed automatically", writes, attempted)
T.finish()
