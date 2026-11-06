-- Public discovery and explicit companion selection; never credentials/tokens.
local Registry = require("schlage.registry")
local Catalog = {}
Catalog.__index = Catalog
function Catalog.new(bridge)
  return setmetatable({ bridge = bridge, watchers = {} }, Catalog)
end

function Catalog:available(child, id)
  local binding = self.bridge.registry:binding(id)
  if not binding then
    return false
  end
  for peer in pairs(C4:GetBoundConsumerDevices(C4:GetDeviceID(), binding.bindingId) or {}) do
    if tonumber(peer) ~= child then
      return false
    end
  end
  return true
end

function Catalog:send(child)
  local watcher, bridge = self.watchers[child], self.bridge
  if not watcher then
    return
  end
  if not bridge:is_child(child) then
    self.watchers[child] = nil
    return
  end
  local devices = JSON:newArray({})
  for id, device in pairs(bridge.registry.devices) do
    if device.supported then
      devices[#devices + 1] =
        { id = id, name = device.name, model = device.model, available = self:available(child, id) }
    end
  end
  C4:SendToDevice(child, "SCHLAGE_CATALOG", {
    SOURCE = tostring(C4:GetDeviceID()),
    NONCE = watcher.nonce,
    JSON = JSON:encode({ ready = bridge.registry.listed, scope = bridge.registry.scope, devices = devices }),
  })
end

function Catalog:publish()
  for child in pairs(self.watchers) do
    self:send(child)
  end
end

function Catalog:execute(command, params)
  if
    command ~= "SCHLAGE_CATALOG_REQUEST"
    and command ~= "SCHLAGE_STOP_CATALOG"
    and command ~= "SCHLAGE_SELECT_LOCK"
    and command ~= "SCHLAGE_RELEASE_LOCK"
  then
    return false
  end
  params = params or {}
  local child, bridge = tonumber(params.CHILD), self.bridge
  if not child or not bridge:is_child(child) or type(params.NONCE) ~= "string" or #params.NONCE > 100 then
    return true
  end
  if command == "SCHLAGE_CATALOG_REQUEST" then
    self.watchers[child] = { nonce = params.NONCE }
    self:send(child)
    return true
  end
  if command == "SCHLAGE_RELEASE_LOCK" then
    local subscription = bridge.children[child]
    if subscription and subscription.nonce == params.NONCE then
      local _, id = bridge.registry:device_for_binding(subscription.binding)
      if bridge.on_unbind then
        bridge.on_unbind(id)
      end
      bridge.children[child] = nil
    end
    return true
  end
  local watcher = self.watchers[child]
  if not watcher or watcher.nonce ~= params.NONCE then
    return true
  end
  if command == "SCHLAGE_STOP_CATALOG" then
    self.watchers[child] = nil
    return true
  end
  if type(params.ID) ~= "string" or type(params.SCOPE) ~= "string" then
    return true
  end
  local reason, binding, device = nil, bridge.registry:binding(params.ID), bridge.registry.devices[params.ID]
  if params.SCOPE ~= bridge.registry.scope or not device or not device.supported or not binding then
    reason = "unavailable"
  elseif not self:available(child, params.ID) then
    reason = "already_assigned"
  else
    local provider = tonumber(C4:GetBoundProviderDevice(child, Registry.INPUT)) or 0
    if provider ~= 0 and provider ~= C4:GetDeviceID() then
      reason = "binding_occupied"
    elseif not bridge:is_bound(binding.bindingId, child) then
      if provider ~= 0 then
        reason = "binding_occupied"
      else
        C4:Bind(C4:GetDeviceID(), binding.bindingId, child, Registry.INPUT, Registry.CLASS)
      end
    end
  end
  C4:SendToDevice(child, "SCHLAGE_SELECTED", {
    SOURCE = tostring(C4:GetDeviceID()),
    NONCE = params.NONCE,
    ID = params.ID or "",
    SCOPE = params.SCOPE or "",
    SUCCESS = reason and "false" or "true",
    REASON = reason or "",
  })
  self:publish()
  return true
end

return Catalog
