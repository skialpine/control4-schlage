local T = require("testlib")
local Device = require("schlage.device")
local JSON = require("JSON"):new({ strictTypes = true })
local function sample(attributes, extra)
  local raw = { deviceId = "synthetic-id", devicetypeId = "be499wifi", connected = true, attributes = attributes }
  for k, v in pairs(extra or {}) do
    raw[k] = v
  end
  return Device.normalize(raw)
end

T.section("Every specified bolt value, missing and invalid values")
for _, row in ipairs({
  { 0, "unlocked" },
  { 1, "locked" },
  { 2, "jammed" },
  { 3, "unknown" },
  { 4, "jammed" },
  { 5, "unlocked" },
  { 6, "locked" },
  { 7, "unknown" },
  { -1, "unknown" },
  { 1.5, "unknown" },
  { "1", "unknown" },
  { false, "unknown" },
  { {}, "unknown" },
}) do
  local device = sample({ lockState = row[1] })
  T.eq("bolt is mapped explicitly", device.bolt, row[2])
  T.eq("fault is separate from locked/unlocked", device.fault, row[2] == "jammed")
end
for _, attributes in ipairs({ {}, false, "invalid" }) do
  T.eq("no valid attributes means unknown", sample(attributes).bolt, "unknown")
end
T.eq("missing attributes means unknown", sample(nil).bolt, "unknown")

T.section("Exact Wi-Fi allowlist and independent connectivity")
for _, kind in ipairs({ "be489wifi", "be489wifi2", "be499wifi" }) do
  T.truthy("known Wi-Fi protocol type", sample({}, { devicetypeId = kind }).supported)
end
for _, kind in ipairs({
  "be499ble",
  "be489ble",
  "be499",
  "BE499WIFI",
  "be499wifi3",
  "be479wifi",
  "future-lock",
  "fe789wifi",
}) do
  T.falsy("unreviewed identifier remains unsupported", sample({}, { devicetypeId = kind }).supported)
end
for _, connected in ipairs({ false, 1, "true", {} }) do
  local device = sample({ lockState = 1 }, { connected = connected })
  T.falsy("only explicit boolean true is connected", device.connected)
  T.eq("disconnection does not change observed bolt", device.bolt, "locked")
end
T.truthy("connected unknown state stays separate", sample({}).connected)

T.section("Telemetry validation without inferring coarse battery state")
for _, level in ipairs({ 0, 25, 100 }) do
  local device = sample({ batteryLevel = level })
  T.eq("valid percentage retained", device.battery, level)
  T.eq("percentage does not imply low state", device.low_battery, nil)
end
for _, level in ipairs({ -1, 101, "50", false, {}, math.huge, 0 / 0 }) do
  T.eq("invalid percentage omitted", sample({ batteryLevel = level }).battery, nil)
end
for _, row in ipairs({ { 0, false }, { 1, true }, { 2, true } }) do
  T.eq("coarse battery mapping", sample({ batteryLowState = row[1] }).low_battery, row[2])
end
for _, low in ipairs({ -1, 3, "1", false, {} }) do
  T.eq("unknown coarse battery omitted", sample({ batteryLowState = low }).low_battery, nil)
end

T.section("Public snapshots strip secrets and index immutable identity")
local list, err, by_id = Device.list(
  JSON:decode(
    '[{"deviceId":"a","devicetypeId":"be499wifi","name":"Door","CAT":"sentinel-CAT","SAT":"sentinel-SAT","users":[{"pin":"sentinel-PIN"}],"attributes":{"lockState":1,"serialNumber":"sentinel-serial","accessCodes":["sentinel-code"]}},{"deviceId":"b","devicetypeId":"unknown"}]'
  )
)
T.eq("valid list", err, nil)
T.eq("indexed by cloud ID", by_id.a, list[1])
T.falsy("unknown device stays visible and unsupported", by_id.b.supported)
local encoded = JSON:encode(list)
for _, marker in ipairs({ "sentinel", "CAT", "SAT", "users", "serialNumber", "accessCodes" }) do
  T.excludes("sensitive fields absent", encoded, marker)
end
local normalized = sample({}, { name = "Door\n1", modelName = "BE499WB" })
T.eq("public names cannot inject log lines", normalized.name, "Door 1")
T.eq("model retained", normalized.model, "BE499WB")
T.finish()
