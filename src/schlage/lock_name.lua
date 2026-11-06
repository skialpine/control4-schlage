-- Prefer the user's generic Door Lock tile, then the native lock proxy or
-- companion name. Follow only this account lock's actual binding chain.
local Name = {}

local function device(id, filename)
  local devices = C4:GetDevices({ DeviceIds = tostring(id) }) or {}
  local value = devices[tonumber(id)] or devices[tostring(id)]
  if
    value
    and value.driverFileName == filename
    and type(value.deviceName) == "string"
    and value.deviceName:match("%S")
  then
    return value.deviceName
  end
end

local function peers(id, binding)
  local result = {}
  for child in pairs(C4:GetBoundConsumerDevices(tonumber(id), binding) or {}) do
    child = tonumber(child)
    if child then
      result[#result + 1] = child
    end
  end
  table.sort(result)
  return result
end

function Name.resolve(account, binding, fallback)
  if not binding then
    return fallback
  end
  local candidates = { {}, {}, {} }
  for _, companion in ipairs(peers(account, binding)) do
    local companion_name = device(companion, "schlage_lock.c4z")
    if companion_name then
      candidates[3][#candidates[3] + 1] = companion_name
      for _, proxy in ipairs(peers(companion, 5001)) do
        local proxy_name = device(proxy, "lock.c4i")
        if proxy_name then
          candidates[2][#candidates[2] + 1] = proxy_name
          for _, tile in ipairs(peers(proxy, 1)) do
            local tile_name = device(tile, "relaysingle_doorlock_c4.c4i")
            if tile_name then
              candidates[1][#candidates[1] + 1] = tile_name
            end
          end
        end
      end
    end
  end
  for _, names in ipairs(candidates) do
    if names[1] then
      return names[1]
    end
  end
  return fallback
end

return Name
