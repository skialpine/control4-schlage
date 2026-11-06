-- Stable account-scoped connections and companion identity.
-- Adapted from the public Nuheat account/companion pattern; see NOTICE.md.
local Registry = {}
Registry.__index = Registry
Registry.CLASS = "SCHLAGE_WIFI_LOCK"
Registry.INPUT = 5002
Registry.DRIVER = "schlage_lock.c4z"

function Registry.new(options)
  return setmetatable({
    bindings = options.bindings,
    publish = options.publish or function() end,
    generation = 0,
    devices = {},
    listed = false,
  }, Registry)
end

function Registry:namespace()
  return self.scope and ("schlage:" .. self.scope) or nil
end

function Registry:binding(id)
  local namespace = self:namespace()
  return namespace and self.bindings:getDynamicBinding(namespace, id) or nil
end

function Registry:all()
  return self:namespace() and self.bindings:getDynamicBindings(self:namespace()) or {}
end

function Registry:invalidate()
  self.generation = self.generation + 1
  for id, binding in pairs(self:all()) do
    self.publish(binding.bindingId, nil, id)
  end
  self.scope, self.devices, self.listed = nil, {}, false
end

function Registry:reconcile(scope, devices)
  assert(type(scope) == "string" and scope ~= "", "Account scope required")
  if self.scope ~= scope then
    self:invalidate()
    self.scope = scope
  end
  self.devices, self.listed = devices, true
  for id, device in pairs(devices) do
    if device.supported then
      self.bindings:getOrAddDynamicBinding(
        self:namespace(),
        id,
        "PROXY",
        true,
        device.name ~= "" and device.name or "Schlage Lock",
        Registry.CLASS
      )
    end
  end
  -- Retain removed connections and project devices. Reappearance reuses the ID.
  for id, binding in pairs(self:all()) do
    local device = devices[id]
    self.publish(binding.bindingId, device and device.supported and device or nil, id)
  end
end

function Registry:device_for_binding(binding_id)
  for id, binding in pairs(self:all()) do
    if binding.bindingId == binding_id then
      return self.devices[id], id
    end
  end
end

return Registry
