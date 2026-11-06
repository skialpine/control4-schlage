require("c4_shim")
require("lib.utils")
local T = require("testlib")
local Companion = require("schlage.companion")
local Bridge = require("schlage.bridge")
local Device = require("schlage.device")
JSON = require("JSON")
local serial, provider, messages, saved, state, identity_writes = 0, 12345, {}, {}, nil, 0
local store = {
  get = function(_, key, default)
    return saved[key] or default
  end,
  set = function(_, key, value)
    if key == "SchlageIdentity" then
      identity_writes = identity_writes + 1
    end
    saved[key] = value
  end,
}
local function nonce()
  serial = serial + 1
  return "test-subscription-" .. serial
end
local child = Companion.new({
  persist = store,
  nonce = nonce,
  provider = function()
    return provider
  end,
  send = function(value)
    messages[#messages + 1] = value
  end,
  on_state = function(value)
    state = value
  end,
})
local snapshot = {
  scope = "scope-A",
  id = "lock-1",
  sequence = 1,
  supported = true,
  connected = true,
  online = true,
  bolt = "locked",
  battery = 65,
  low_battery = false,
  updated_at = 100,
  name = "Test lock",
  CAT = "sentinel-CAT",
  session = "sentinel-token",
}

T.section("Startup, offline before handoff, telemetry and ordering")
child:refresh()
T.falsy("startup is offline", state.online)
local first = messages[#messages]
T.truthy("fresh handoff accepted", child:take(provider, first, snapshot))
T.truthy("online independent of bolt changes", state.online)
T.eq("low-battery false retained", state.low_battery, false)
T.eq("public identity persisted", saved.SchlageIdentity, { scope = "scope-A", id = "lock-1" })
T.eq("new identity is saved once", identity_writes, 1)
T.excludes("token stripped from child state", JSON:encode(state), "sentinel")
snapshot.sequence, snapshot.connected, snapshot.online = 3, false, false
child:take(provider, first, snapshot)
T.falsy("disconnected even with unchanged locked bolt", state.online)
T.eq("last observed bolt retained", state.bolt, "locked")
T.eq("telemetry updates do not resave identical identity", identity_writes, 1)
snapshot.sequence, snapshot.online, snapshot.connected = 2, true, true
T.falsy("older handoff rejected", child:take(provider, first, snapshot))
T.falsy("older handoff cannot restore online", state.online)

T.section("Rebind, unbind, restart and late messages")
child:refresh()
local second = messages[#messages]
snapshot.sequence = 100
T.falsy("old subscription after refresh rejected", child:take(provider, first, snapshot))
T.truthy("new subscription accepted", child:take(provider, second, snapshot))
provider = 0
child:refresh()
T.falsy("unbinding takes child offline", state.online)
T.eq("unbinding does not fabricate a bolt transition", state.bolt, "locked")
T.falsy("old provider cannot update unbound child", child:take(12345, second, snapshot))
provider = 54321
child:refresh()
local third = messages[#messages]
T.falsy("old account callback after rebind rejected", child:take(12345, third, snapshot))
snapshot.sequence, snapshot.id, snapshot.scope = 1, "lock-2", "scope-B"
T.truthy("explicit new binding claims new identity", child:take(provider, third, snapshot))
T.eq("identity tracks new binding", saved.SchlageIdentity.id, "lock-2")
T.eq("new binding persists its changed identity", identity_writes, 2)
local restarted = Companion.new({
  persist = store,
  nonce = nonce,
  provider = function()
    return provider
  end,
  send = function(value)
    messages[#messages + 1] = value
  end,
  on_state = function(value)
    state = value
  end,
})
restarted:refresh()
T.falsy("restart offline until fresh handoff", state.online)
T.eq("restart preserves public identity for idempotent Add", restarted.identity.id, "lock-2")
T.falsy("pre-restart handoff rejected", restarted:take(provider, third, snapshot))

T.section("Real project adapter handoff contains public fields only")
local bindings = require("lib.bindings")
bindings:reset()
function C4:GetDevicesByC4iName(filename)
  return filename == "schlage_lock.c4z" and { [200] = "Test companion" } or {}
end
local queued = {}
local function schedule(_, callback)
  queued[#queued + 1] = callback
  return { cancel = function() end }
end
local bridge = Bridge.new({
  bindings = bindings,
  schedule = schedule,
  nonce = nonce,
  now = function()
    return 100
  end,
})
local normalized = Device.normalize({
  deviceId = "cloud-1",
  devicetypeId = "be499wifi",
  connected = true,
  CAT = "sentinel-CAT",
  SAT = "sentinel-SAT",
  attributes = { lockState = 1, PIN = "sentinel-PIN" },
})
bridge:ingest("scope-C", { normalized })
local binding = bridge.registry:binding("cloud-1").bindingId
C4:Bind(C4:GetDeviceID(), binding, 200, 5002, "SCHLAGE_WIFI_LOCK")
local packet
function C4:SendToDevice(id, command, params)
  packet = { id = id, command = command, params = params }
end
bridge:request(binding, "REFRESH_STATE", { CHILD = "999", NONCE = "nope" })
T.eq("unrelated child cannot subscribe", packet, nil)
bridge:request(binding, "REFRESH_STATE", { CHILD = "200", NONCE = "current" })
T.eq("handoff goes only to verified bound companion", packet.id, 200)
local data = JSON:decode(packet.params.JSON)
T.truthy("current connected model online", data.online)
T.eq("cloud ID routed correctly", data.id, "cloud-1")
local routed
bridge.on_command = function(id, action)
  routed = { id, action }
end
bridge:request(binding, "LOCK_INTENT", { CHILD = "999", NONCE = "current", ACTION = "UNLOCK" })
T.eq("unrelated driver cannot issue lock intents", routed, nil)
bridge:request(binding, "LOCK_INTENT", { CHILD = "200", NONCE = "obsolete", ACTION = "UNLOCK" })
T.eq("obsolete child subscription cannot issue intents", routed, nil)
bridge:request(binding, "LOCK_INTENT", { CHILD = "200", NONCE = "current", ACTION = "UNLOCK", ID = "unrelated-target" })
T.eq("target derives from actual binding, not supplied ID", routed, { "cloud-1", "UNLOCK" })
T.excludes("raw cloud secrets stripped", packet.params.JSON, "sentinel")
bridge:stale()
data = JSON:decode(packet.params.JSON)
T.falsy("stale account pushes offline", data.online)
T.eq("stale account preserves bolt", data.bolt, "locked")
bridge:ingest("scope-C", {})
data = JSON:decode(packet.params.JSON)
T.falsy("successful removal pushes offline", data.online)
T.eq("removal has no fabricated bolt value", data.bolt, nil)
bridge:invalidate()
bridge:request(binding, "REFRESH_STATE", { CHILD = "200", NONCE = "new-start" })
bridge:ingest("scope-C", { normalized })
T.eq("account restart uses child's new subscription", packet.params.NONCE, "new-start")
T.truthy("account recovery restores online", JSON:decode(packet.params.JSON).online)
bridge:destroy()
T.falsy("destruction takes companion offline", JSON:decode(packet.params.JSON).online)
T.finish()
