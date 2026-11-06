-- Composer programming built on the template's stable event/conditional IDs.
local Events = require("lib.events")
local Conditionals = require("lib.conditionals")
local Programming = {}
Programming.__index = Programming
local namespace = "schlage_lock"
local definitions = {
  { "online", "Online" },
  { "offline", "Offline" },
  { "locked", "Locked" },
  { "unlocked", "Unlocked" },
  { "jammed", "Jammed" },
  { "low_battery", "Low Battery" },
  { "confirmed", "Command Confirmed" },
  { "failed", "Command Failed" },
}
local failures = { unconfirmed = true, rejected = true, expired = true, authentication_failed = true, fault = true }

function Programming.new(options)
  options = options or {}
  return setmetatable(
    { events = options.events or Events, conditions = options.conditions or Conditionals, state = {} },
    Programming
  )
end

function Programming:start()
  -- Restore this namespace without deleting hundreds of unrelated event IDs.
  for _, event in pairs(self.events:getEvents()[namespace] or {}) do
    C4:AddEvent(event.eventId, event.name, event.description)
  end
  for _, item in ipairs(definitions) do
    self.events:getOrAddEvent(namespace, item[1], item[2], "NAME " .. item[2])
  end
  for _, item in ipairs({
    {
      "online",
      "is online",
      function(s)
        return s.online == true
      end,
    },
    {
      "locked",
      "is locked",
      function(s)
        return s.online == true and s.bolt == "locked"
      end,
    },
    {
      "unlocked",
      "is unlocked",
      function(s)
        return s.online == true and s.bolt == "unlocked"
      end,
    },
    {
      "jammed",
      "is jammed",
      function(s)
        return s.online == true and s.bolt == "jammed"
      end,
    },
    {
      "low_battery",
      "has low battery",
      function(s)
        return s.online == true and s.low_battery == true
      end,
    },
  }) do
    local predicate = item[3]
    self.conditions:upsertConditional(namespace, item[1], {
      type = "SIMPLE",
      condition_statement = item[2],
      description = "NAME " .. item[2],
    }, function()
      return predicate(self.state)
    end)
  end
end

function Programming:update(state, identity)
  identity = identity or {}
  if self.id ~= identity.id or self.scope ~= identity.scope then
    self.state = {}
    self.id, self.scope = identity.id, identity.scope
  end
  local old = self.state
  if old.online ~= nil and old.online ~= (state.online == true) then
    self.events:fire(namespace, state.online and "online" or "offline")
  end
  -- Initial synchronization and unknown state do not assert physical movement.
  if state.online and old.bolt and old.bolt ~= "unknown" and old.bolt ~= state.bolt then
    if state.bolt == "locked" or state.bolt == "unlocked" or state.bolt == "jammed" then
      self.events:fire(namespace, state.bolt)
    end
  end
  if state.online and state.low_battery == true and old.low_battery ~= true and old.bolt ~= nil then
    self.events:fire(namespace, "low_battery")
  end
  local pending = old.outcome == "queued" or old.outcome == "pending"
  if pending and state.outcome == "confirmed" then
    self.events:fire(namespace, "confirmed")
  elseif pending and (failures[state.outcome] or (state.outcome or ""):match("^rejected:")) then
    self.events:fire(namespace, "failed")
  end
  self.state = {
    online = state.online == true,
    bolt = state.bolt,
    low_battery = state.low_battery,
    outcome = state.outcome,
  }
end

return Programming
