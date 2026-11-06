require("c4_shim")
local T = require("testlib")
local Programming = require("schlage.programming")
local events = require("lib.events")
local fired = {}
function C4:FireEventByID(id)
  fired[id] = (fired[id] or 0) + 1
end
local p = Programming.new()
p:start()
local ids = events:getEvents().schlage_lock
local function count(key)
  return fired[ids[key].eventId] or 0
end
local function condition(key)
  return TestCondition(require("lib.conditionals"):getConditionals().schlage_lock[key].name)
end
local a = { id = "a", scope = "scope" }
T.section("Initial synchronization is not a physical transition")
p:update({ online = false, bolt = "unknown", outcome = "none" }, a)
p:update({ online = true, bolt = "locked", outcome = "none" }, a)
T.eq("fresh availability is reported once", count("online"), 1)
T.eq("startup does not fire a physical Locked event", count("locked"), 0)
T.truthy("online condition reflects availability", condition("online"))
T.truthy("locked condition reflects observed bolt", condition("locked"))
p:update({ online = true, bolt = "locked", outcome = "pending" }, a)
p:update({ online = true, bolt = "unlocked", outcome = "confirmed" }, a)
T.eq("observed transition fires Unlocked", count("unlocked"), 1)
T.eq("command completion has its own event", count("confirmed"), 1)
p:update({ online = true, bolt = "unlocked", outcome = "confirmed" }, a)
T.eq("same observation does not refire transition", count("unlocked"), 1)
T.eq("same outcome does not refire confirmation", count("confirmed"), 1)

T.section("Fault, low battery, failure, offline and reassignment remain distinct")
p:update({ online = true, bolt = "unlocked", outcome = "pending" }, a)
p:update({ online = true, bolt = "jammed", low_battery = true, outcome = "fault" }, a)
T.eq("jam event comes from observed fault", count("jammed"), 1)
T.eq("battery is independent of bolt state", count("low_battery"), 1)
T.eq("failed command has its own event", count("failed"), 1)
T.truthy("jam condition available for programming", condition("jammed"))
p:update({ online = false, bolt = "jammed", low_battery = true, outcome = "fault" }, a)
T.eq("offline event does not require a bolt change", count("offline"), 1)
T.falsy("offline data is not a current jam condition", condition("jammed"))
T.falsy("offline data is not a current low-battery condition", condition("low_battery"))
p:update({ online = true, bolt = "unlocked", outcome = "none" }, { id = "b", scope = "scope" })
T.eq("reassignment does not claim the previous lock moved", count("unlocked"), 1)
local previous = ids.locked.eventId
local restarted = Programming.new()
restarted:start()
T.eq("event IDs survive reload for existing programming", events:getEvents().schlage_lock.locked.eventId, previous)
restarted:update({ online = true, bolt = "locked", outcome = "confirmed" }, a)
T.eq("reload initial snapshot does not trigger Locked", count("locked"), 0)
T.eq("reload initial outcome does not trigger Command Confirmed", count("confirmed"), 1)
T.finish()
