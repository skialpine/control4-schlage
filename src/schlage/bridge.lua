-- Control4 project adapter. Only normalized, public snapshots cross this boundary.
local Registry = require("schlage.registry")
local Catalog = require("schlage.catalog")
local Bridge = {}
Bridge.__index = Bridge

function Bridge.new(options)
  local self = setmetatable({
    bindings = options.bindings,
    schedule = options.schedule,
    now = options.now or os.time,
    children = {},
    sequence = 0,
    alive = true,
    nonce = options.nonce,
    read_time = options.read_time,
    outcomes = {},
    observed = {},
    on_change = options.on_change or function() end,
  }, Bridge)
  self.registry = Registry.new({
    bindings = self.bindings,
    publish = function(binding, device, id)
      self:publish(binding, device, id)
    end,
  })
  self.catalog = Catalog.new(self)
  return self
end

function Bridge:is_child(id)
  local devices = C4:GetDevicesByC4iName(Registry.DRIVER) or {}
  return devices[id] ~= nil or devices[tostring(id)] ~= nil
end

function Bridge:is_bound(binding, child)
  local peers = C4:GetBoundConsumerDevices(C4:GetDeviceID(), binding) or {}
  return self:is_child(child) and (peers[child] ~= nil or peers[tostring(child)] ~= nil)
end

function Bridge:execute(command, params)
  return self.catalog:execute(command, params)
end

function Bridge:request(binding, command, params)
  if command ~= "REFRESH_STATE" and command ~= "LOCK_INTENT" then
    return false
  end
  params = params or {}
  local child = tonumber(params.CHILD)
  if not child or not self:is_bound(binding, child) or type(params.NONCE) ~= "string" or #params.NONCE > 100 then
    return true
  end
  if command == "LOCK_INTENT" then
    local subscription = self.children[child]
    if subscription and subscription.binding == binding and subscription.nonce == params.NONCE then
      local _, id = self.registry:device_for_binding(binding)
      if id and self.on_command then
        self.on_command(id, params.ACTION)
      end
    end
    return true
  end
  local previous = self.children[child]
  if previous and (previous.nonce ~= params.NONCE or previous.binding ~= binding) and self.on_unbind then
    local _, id = self.registry:device_for_binding(previous.binding)
    self.on_unbind(id)
  end
  self.children[child] = { binding = binding, nonce = params.NONCE }
  local device, id = self.registry:device_for_binding(binding)
  self:publish(binding, device and device.supported and device or nil, id)
  return true
end

function Bridge:publish(binding, device, id)
  self.sequence = self.sequence + 1
  local snapshot = { id = id, scope = self.registry.scope, sequence = self.sequence, online = false }
  if device then
    for _, key in ipairs({
      "id",
      "name",
      "model",
      "device_type",
      "supported",
      "connected",
      "bolt",
      "fault",
      "battery",
      "low_battery",
    }) do
      snapshot[key] = device[key]
    end
    snapshot.online = device.supported and device.connected and self.fresh == true
    snapshot.updated_at = self.observed[id]
  end
  local outcome = self.outcomes[id]
  snapshot.outcome, snapshot.intent = outcome and outcome.outcome or "none", outcome and outcome.intent or ""
  for child, subscription in pairs(self.children) do
    if subscription.binding == binding then
      if self:is_bound(binding, child) then
        C4:SendToDevice(
          child,
          "SCHLAGE_SNAPSHOT",
          { SOURCE = tostring(C4:GetDeviceID()), NONCE = subscription.nonce, JSON = JSON:encode(snapshot) }
        )
      else
        self.children[child] = nil
      end
    end
  end
end

function Bridge:ingest(scope, devices)
  local by_id = {}
  if self.registry.scope ~= scope then
    self.outcomes = {}
  end
  for _, device in ipairs(devices) do
    by_id[device.id] = device
    self.observed[device.id] = self.read_time and self.read_time(device.id) or self.now()
  end
  self.fresh, self.updated_at = true, self.now()
  self.registry:reconcile(scope, by_id)
  self.catalog:publish()
end

function Bridge:update(device)
  if not self.registry.devices[device.id] then
    return
  end
  self.registry.devices[device.id] = device
  self.observed[device.id] = self.read_time and self.read_time(device.id) or self.now()
  local binding = self.registry:binding(device.id)
  if binding then
    self:publish(binding.bindingId, device, device.id)
  end
end

function Bridge:outcome(id, outcome, intent)
  self.outcomes[id] = { outcome = outcome, intent = intent }
  local binding = self.registry:binding(id)
  if binding then
    self:publish(binding.bindingId, self.registry.devices[id], id)
  end
end

function Bridge:stale()
  self.fresh = false
  for id, binding in pairs(self.registry:all()) do
    local device = self.registry.devices[id]
    self:publish(binding.bindingId, device and device.supported and device or nil, id)
  end
end

function Bridge:reset_children()
  for _, namespace in pairs(self.bindings:getBindings()) do
    for _, binding in pairs(namespace) do
      if binding.class == Registry.CLASS then
        for child in pairs(C4:GetBoundConsumerDevices(C4:GetDeviceID(), binding.bindingId) or {}) do
          child = tonumber(child)
          if child and self:is_child(child) then
            C4:SendToDevice(child, "SCHLAGE_ACCOUNT_RESET", { SOURCE = tostring(C4:GetDeviceID()) })
          end
        end
      end
    end
  end
  for child in pairs(C4:GetDevicesByC4iName(Registry.DRIVER) or {}) do
    C4:SendToDevice(tonumber(child), "SCHLAGE_CATALOG_CHANGED", { SOURCE = tostring(C4:GetDeviceID()) })
  end
end

function Bridge:invalidate()
  self.fresh = false
  self.registry:invalidate()
  self.outcomes, self.observed = {}, {}
  self.catalog:publish()
end

function Bridge:destroy(quiet)
  if quiet then
    self.children = {}
    self.catalog.watchers = {}
  end
  self:invalidate()
  self.alive = false
  self.catalog.watchers = {}
end

return Bridge
