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
T.section("Damaged saved programming does not prevent companion startup")
local persist = require("lib.persist")
local conditions = require("lib.conditionals")
local saved_id = ids.locked.eventId
local saved_condition = conditions:getConditionals().schlage_lock.locked.conditionalId
local saved_events = events:getEvents()
saved_events.schlage_lock.unlocked = { name = "Unlocked", description = "NAME Unlocked" }
saved_events.schlage_lock.failed = "broken entry"
saved_events.schlage_lock.online = { eventId = ids.online.eventId } -- missing text
saved_events.schlage_lock.obsolete = false
saved_events.unrelated = { retained = { eventId = 900, name = "Other", description = "Other" } }
saved_events.bad_namespace = true
persist:set("Events", saved_events)
local saved_conditions = conditions:getConditionals()
saved_conditions.schlage_lock.online = { name = "missing id" }
saved_conditions.schlage_lock.jammed = false
saved_conditions.bad_namespace = "broken"
persist:set("Conditionals", saved_conditions)
C4:AddEvent(900, "Other", "Other")
local recovered = Programming.new()
recovered:start()
T.eq("valid event ID retained", events:getEvents().schlage_lock.locked.eventId, saved_id)
T.eq("valid conditional ID retained", conditions:getConditionals().schlage_lock.locked.conditionalId, saved_condition)
T.truthy("event without ID repaired", events:getEvents().schlage_lock.unlocked.eventId)
T.eq("event missing text repaired", ShimEvents()[ids.online.eventId].name, "Online")
T.truthy("non-table event repaired", events:getEvents().schlage_lock.failed.eventId)
T.truthy("unrelated event is not deleted", ShimEvents()[900])
T.truthy("damaged conditional repaired", conditions:getConditionals().schlage_lock.jammed.conditionalId)
for _, conditional in pairs(GetConditionals()) do
  T.truthy("restored conditions have sort order", conditional.sort_order)
end
persist:set("Events", { schlage_lock = "broken namespace", unrelated = saved_events.unrelated })
persist:set("Conditionals", { schlage_lock = false })
Programming.new():start()
T.truthy("malformed namespace rebuilt", events:getEvents().schlage_lock.locked.eventId)
T.truthy("malformed conditional namespace rebuilt", conditions:getConditionals().schlage_lock.locked.conditionalId)
T.truthy("unrelated event remains after namespace repair", ShimEvents()[900])
T.finish()
