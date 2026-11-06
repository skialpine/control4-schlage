-- Companion subscription. Account/session secrets never enter this module.
local Companion = {}
Companion.__index = Companion

function Companion.new(options)
  local identity = options.persist:get("SchlageIdentity", {})
  if type(identity) ~= "table" or type(identity.id) ~= "string" or type(identity.scope) ~= "string" then
    identity = {}
  end
  return setmetatable({
    nonce = options.nonce,
    provider = options.provider,
    send = options.send,
    on_state = options.on_state,
    persist = options.persist,
    accepts = options.accepts,
    on_identity = options.on_identity,
    sequence = 0,
    identity = identity,
    state = { online = false },
  }, Companion)
end

function Companion:suspend()
  self.subscription, self.sequence, self.account = self.nonce(), 0, 0
  self.state = { online = false, bolt = "unknown", outcome = "none" }
  self.on_state(self.state)
end

function Companion:refresh()
  self.subscription, self.sequence = self.nonce(), 0
  self.state.online = false
  self.on_state(self.state)
  self.account = self.provider()
  if self.account and self.account ~= 0 then
    self.send(self.subscription)
  end
end

function Companion:take(source, nonce, data)
  if self.accepts and not self.accepts(data) then
    return false
  end
  if
    source ~= self.account
    or source ~= self.provider()
    or nonce ~= self.subscription
    or type(data) ~= "table"
    or type(data.sequence) ~= "number"
    or data.sequence ~= data.sequence
    or data.sequence == math.huge
    or data.sequence % 1 ~= 0
    or data.sequence <= self.sequence
  then
    return false
  end
  self.sequence = data.sequence
  local outcomes = {
    none = true,
    queued = true,
    pending = true,
    expired = true,
    cancelled = true,
    confirmed = true,
    unconfirmed = true,
    fault = true,
    rejected = true,
    authentication_failed = true,
    ["rejected: unknown_device"] = true,
    ["rejected: unsupported_device"] = true,
    ["rejected: offline"] = true,
    ["rejected: state_unknown"] = true,
    ["rejected: invalid_command"] = true,
  }
  -- Copy an allowlist even when the sender is another project driver.
  local state = {
    online = data.online == true,
    bolt = self.state.bolt or "unknown",
    fault = self.state.fault == true,
    battery = self.state.battery,
    low_battery = self.state.low_battery,
    updated_at = self.state.updated_at,
    name = self.state.name,
    model = self.state.model,
    supported = self.state.supported,
  }
  state.outcome = outcomes[data.outcome] and data.outcome or "none"
  state.intent = (data.intent == "lock" or data.intent == "unlock") and data.intent or ""
  if type(data.id) == "string" and type(data.scope) == "string" then
    if self.identity.id ~= data.id or self.identity.scope ~= data.scope then
      self.identity = { id = data.id, scope = data.scope }
      self.persist:set("SchlageIdentity", self.identity)
    end
    if self.on_identity then
      self.on_identity(self.identity)
    end
  end
  if data.bolt ~= nil then
    local states = { locked = true, unlocked = true, jammed = true, unknown = true }
    state.bolt = states[data.bolt] and data.bolt or "unknown"
    state.fault = state.bolt == "jammed"
    state.battery = type(data.battery) == "number" and data.battery >= 0 and data.battery <= 100 and data.battery or nil
    state.low_battery = type(data.low_battery) == "boolean" and data.low_battery or nil
    -- Preserve false: Lua's and/or idiom cannot represent a false optional value.
    if data.low_battery == false then
      state.low_battery = false
    end
    state.updated_at = type(data.updated_at) == "number" and data.updated_at or nil
    state.name = type(data.name) == "string" and data.name or ""
    state.model = type(data.model) == "string" and data.model or ""
    state.supported = data.supported == true
    state.online = state.online and state.supported and data.connected == true
  else
    state.online = false
  end
  self.state = state
  self.on_state(state)
  return true
end

return Companion
