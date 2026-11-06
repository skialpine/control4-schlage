-- Public device model. Never retain a raw cloud object (CAT/SAT, users or PINs).
-- Protocol reference: pinned pyschlage device.py / lock.py; see NOTICE.md.
local Device = {}

-- Exact transport identifiers only. A model-family prefix also matches BLE locks.
local wifi_types = { be489wifi = true, be489wifi2 = true, be499wifi = true }
local states = { [0] = "unlocked", [1] = "locked", [2] = "jammed", [4] = "jammed", [5] = "unlocked", [6] = "locked" }

local function text(value)
  return type(value) == "string" and value:gsub("[%z\1-\31\127]", " "):sub(1, 120) or ""
end

function Device.normalize(raw)
  if
    type(raw) ~= "table"
    or type(raw.deviceId) ~= "string"
    or raw.deviceId == ""
    or type(raw.devicetypeId) ~= "string"
  then
    return nil, { category = "malformed_response" }
  end
  local attributes = type(raw.attributes) == "table" and raw.attributes or {}
  local bolt = type(attributes.lockState) == "number" and states[attributes.lockState] or "unknown"
  bolt = bolt or "unknown"
  local battery = attributes.batteryLevel
  if type(battery) ~= "number" or battery ~= battery or battery < 0 or battery > 100 then
    battery = nil
  end
  local low = attributes.batteryLowState
  local low_battery
  if low == 0 then
    low_battery = false
  elseif low == 1 or low == 2 then
    low_battery = true
  end
  return {
    id = raw.deviceId,
    name = text(raw.name),
    device_type = text(raw.devicetypeId),
    model = text(raw.modelName),
    supported = wifi_types[raw.devicetypeId] == true,
    connected = raw.connected == true,
    bolt = bolt,
    fault = bolt == "jammed",
    battery = battery,
    low_battery = low_battery,
  }
end

function Device.list(raw)
  -- The strict JSON codec distinguishes a valid empty list from an error object.
  if type(raw) ~= "table" or tostring(raw) ~= "JSON array" then
    return nil, { category = "malformed_response" }
  end
  local list, by_id = {}, {}
  for _, value in ipairs(raw) do
    local device, err = Device.normalize(value)
    if not device or by_id[device.id] then
      return nil, err or { category = "malformed_response" }
    end
    list[#list + 1], by_id[device.id] = device, device
  end
  return list, nil, by_id
end

return Device
