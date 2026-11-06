require("c4_shim")
require("lib.utils")
local T = require("testlib")
local Bridge = require("schlage.bridge")
local Device = require("schlage.device")
local bindings = require("lib.bindings")
JSON = require("JSON")
bindings:reset()
local messages, bind_calls, cancelled = {}, 0, nil
function C4:GetDevicesByC4iName(name)
  return name == "schlage_lock.c4z" and { [201] = "Kitchen Lock 1", [202] = "Kitchen Lock 2" } or {}
end
function C4:SendToDevice(id, command, params)
  messages[#messages + 1] = { id = id, command = command, params = params }
end
function C4:AddDevice()
  error("selection must not create project devices")
end
function C4:RoomGetId()
  error("selection must not restrict room placement")
end
local original_bind = C4.Bind
function C4:Bind(...)
  bind_calls = bind_calls + 1
  return original_bind(self, ...)
end
local bridge = Bridge.new({ bindings = bindings })
bridge.on_unbind = function(id)
  cancelled = id
end
local function device(id, name)
  return Device.normalize({
    deviceId = id,
    name = name,
    devicetypeId = "be499wifi",
    connected = true,
    CAT = "sentinel-CAT",
    attributes = { lockState = 1, PIN = "sentinel-PIN" },
  })
end
bridge:ingest("scope-A", { device("a", "Front Door"), device("b", "Garage Door") })
local function request(child, command, nonce, id, scope)
  bridge:execute(command, { CHILD = tostring(child), NONCE = nonce, ID = id, SCOPE = scope or "scope-A" })
end
local function last(command, child)
  for i = #messages, 1, -1 do
    if messages[i].command == command and messages[i].id == child then
      return messages[i].params
    end
  end
end
T.section("Catalog is public, scoped, and available before binding")
request(999, "SCHLAGE_CATALOG_REQUEST", "foreign")
T.eq("unrelated project driver receives no catalog", #messages, 0)
request(201, "SCHLAGE_CATALOG_REQUEST", "child-1")
local catalog = last("SCHLAGE_CATALOG", 201)
T.truthy("catalog available without a connection", catalog)
T.excludes("catalog contains no raw secrets", catalog.JSON, "sentinel")
T.eq("two discovered locks available", #JSON:decode(catalog.JSON).devices, 2)
request(201, "SCHLAGE_SELECT_LOCK", "obsolete", "a")
T.eq("obsolete catalog cannot select", bind_calls, 0)
request(201, "SCHLAGE_SELECT_LOCK", "child-1", "a")
T.eq(
  "explicit selection binds exact lock",
  C4:GetBoundConsumerDevices(C4:GetDeviceID(), bridge.registry:binding("a").bindingId),
  { [201] = "Device 201" }
)
T.eq("selection acknowledged", last("SCHLAGE_SELECTED", 201).SUCCESS, "true")
request(201, "SCHLAGE_SELECT_LOCK", "child-1", "a")
T.eq("repeat selection is idempotent", bind_calls, 1)

T.section("Two locks in the same room, duplicate prevention, and lifecycle scope")
request(202, "SCHLAGE_CATALOG_REQUEST", "child-2")
request(202, "SCHLAGE_SELECT_LOCK", "child-2", "a")
T.eq("same physical lock cannot be silently duplicated", last("SCHLAGE_SELECTED", 202).REASON, "already_assigned")
request(202, "SCHLAGE_SELECT_LOCK", "child-2", "b")
T.eq("second companion selects another lock independently of room", last("SCHLAGE_SELECTED", 202).SUCCESS, "true")
T.eq("two distinct selected connections", bind_calls, 2)
bridge:request(bridge.registry:binding("a").bindingId, "REFRESH_STATE", { CHILD = "201", NONCE = "subscription" })
request(201, "SCHLAGE_RELEASE_LOCK", "subscription")
T.eq("reselection cancels old pending lock commands", cancelled, "a")
C4:Unbind(201, 5002)
bridge:ingest("scope-B", { device("a", "Different account") })
request(201, "SCHLAGE_SELECT_LOCK", "child-1", "a", "scope-A")
T.eq("old cloud-account scope cannot bind", last("SCHLAGE_SELECTED", 201).REASON, "unavailable")
T.eq("old scope cannot restore input connection", C4:GetBoundProviderDevice(201, 5002), 0)
bridge:destroy()
T.finish()
