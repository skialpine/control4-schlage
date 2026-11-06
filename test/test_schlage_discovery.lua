require("c4_shim")
local T = require("testlib")
local Client = require("schlage.client")
local JSON = require("JSON"):new({ strictTypes = true })
local pending, value, error_value, calls = nil, nil, nil, 0
local account = {
  generation = 0,
  ensure = function(_, callback)
    callback({ access_token = "synthetic-access" })
  end,
}
local transport = {
  devices = function(_, token, callback)
    T.eq("access token used", token, "synthetic-access")
    pending = callback
    calls = calls + 1
    return { cancel = function() end }
  end,
}
local client = Client.new(account, transport)
local function result(a, b)
  value, error_value = a, b
end
T.section("Normalized public discovery, valid empty account, malformed listing")
client:discover(result)
pending(
  JSON:decode(
    '[{"deviceId":"synthetic-1","name":"Test","devicetypeId":"be499wifi","modelName":"BE499WB","CAT":"sentinel-CAT","SAT":"sentinel-SAT","attributes":{"accessCodes":["1234"]}}]'
  )
)
T.eq("public snapshot only", value, {
  {
    id = "synthetic-1",
    name = "Test",
    device_type = "be499wifi",
    model = "BE499WB",
    supported = true,
    connected = false,
    bolt = "unknown",
    fault = false,
  },
})
client:discover(result)
pending(JSON:decode("[]"))
T.eq("empty account succeeds", value, {})
T.eq("empty account has no error", error_value, nil)
for _, body in ipairs({
  "{}",
  '{"error":"not a device list"}',
  '[{"name":"missing ID"}]',
  '[{"deviceId":"dup","devicetypeId":"be499wifi"},{"deviceId":"dup","devicetypeId":"be499wifi"}]',
}) do
  client:discover(result)
  pending(JSON:decode(body))
  T.eq("malformed listing fails", error_value.category, "malformed_response")
  T.eq("failure never becomes empty account", value, nil)
end
T.section("Failure categories and lifecycle isolation")
for _, category in ipairs({ "unauthorized", "rate_limited", "transport_error" }) do
  client:discover(result)
  pending(nil, { category = category })
  if category == "unauthorized" then
    pending(nil, { category = category })
  end
  T.eq("failure preserved", error_value.category, category)
end
T.section("Failed and out-of-order listings preserve the current registry")
local fixture = '[{"deviceId":"one","name":"Current","devicetypeId":"be499wifi"}]'
client:discover(result)
pending(JSON:decode(fixture))
client:discover(result)
pending(nil, { category = "transport_error" })
T.eq("failure retains known ID", client.devices.one.name, "Current")
client:discover(result)
local earlier = pending
client:discover(result)
pending(JSON:decode(fixture:gsub("Current", "Newer")))
earlier(JSON:decode(fixture:gsub("Current", "Older")))
T.eq("late earlier listing cannot overwrite registry", client.devices.one.name, "Newer")
T.eq("superseded caller receives cancellation", error_value.category, "cancelled")
client:discover(result)
pending(JSON:decode("[]"))
T.eq("successful empty listing removes all entries", client.devices, {})
client:discover(result)
account.generation = account.generation + 1
pending(JSON:decode("[]"))
T.eq("old generation rejected", error_value.category, "cancelled")
client:discover(result)
local old = pending
client:cancel()
old(JSON:decode("[]"))
T.eq("cancelled read cannot revive discovery", error_value.category, "cancelled")
T.finish()
