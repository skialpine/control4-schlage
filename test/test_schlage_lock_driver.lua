require("c4_shim")
local T = require("testlib")
local messages, properties, variables, added, provider = {}, {}, {}, {}, 42
function C4:GetDevicesByC4iName(name)
  return name == "schlage_account.c4z" and { [42] = "Schlage Account" } or {}
end
function C4:GetBoundProviderDevice()
  return provider
end
function C4:UpdateProperty(name, value)
  properties[name] = value
end
function C4:AddVariable(name, value, kind, readonly)
  added[#added + 1] = { name = name, kind = kind, readonly = readonly }
  variables[name] = value
end
function C4:SetVariable(name, value)
  variables[name] = value
end
function C4:SendToProxy(binding, command, params, kind)
  messages[#messages + 1] = { binding = binding, command = command, params = params, kind = kind }
end
local function last(command)
  for i = #messages, 1, -1 do
    if messages[i].command == command then
      return messages[i]
    end
  end
end
local function count(command)
  local n = 0
  for _, m in ipairs(messages) do
    if m.command == command then
      n = n + 1
    end
  end
  return n
end
dofile("drivers/schlage_lock/driver.lua")
OnDriverInit()
T.eq("all programming variables registered during Init", #added, 9)
T.truthy("programming state is read-only", added[1].readonly)
T.eq("no network or proxy operation during Init", #messages, 0)
OnDriverLateInit()
Properties["Log Mode"], Properties["Log Level"] = "Print and Log", "6 - Ultra"
OnPropertyChanged("Log Mode")
local function quiet(label)
  T.falsy(label, DEBUGPRINT or DEBUG_URL or DEBUG_RFN or DEBUG_WEBSOCKET or DEBUG_TIMER)
end
quiet("Ultra never enables raw companion tracing")
for _, mode in ipairs({ "Off", "Print", "Log", "Print and Log" }) do
  Properties["Log Mode"] = mode
  OnPropertyChanged("Log Mode")
  Properties["Log Level"] = "3 - Info"
  OnPropertyChanged("Log Level")
  Properties["Log Level"] = "6 - Ultra"
  OnPropertyChanged("Log Level")
  quiet("Ultra setting changes keep raw companion dumps off: " .. mode)
end
T.eq("structured companion Ultra logging remains available", require("lib.logging"):getLogLevel(), 6)
T.eq("startup offline", variables.ONLINE, "0")
T.eq("startup asks its account for public state", last("REFRESH_STATE").binding, 5002)
local nonce = last("REFRESH_STATE").params.NONCE
local JSON = require("JSON")
local sequence = 0
local function handoff(bolt, connected, battery, low, outcome, intent)
  sequence = sequence + 1
  ExecuteCommand("SCHLAGE_SNAPSHOT", {
    SOURCE = "42",
    NONCE = nonce,
    JSON = JSON:encode({
      sequence = sequence,
      scope = "synthetic-scope",
      id = "synthetic-id",
      online = connected,
      connected = connected,
      supported = true,
      bolt = bolt,
      name = "Test Door",
      model = "BE499WB",
      battery = battery,
      low_battery = low,
      updated_at = 1,
      outcome = outcome or "none",
      intent = intent or "",
      CAT = "sentinel-CAT",
      PIN = "sentinel-PIN",
    }),
  })
end
T.section("Proxy dispatch uses its account binding and no optimistic state")
handoff("locked", true, 88, false)
T.eq(
  "first observed lock state initializes the native proxy",
  last("LOCK_STATUS_INITIALIZE").params.LOCK_STATUS,
  "locked"
)
T.eq("initial synchronization creates no native movement event", count("LOCK_STATUS_CHANGED"), 0)
T.eq("initialization is not labeled as an external movement", last("LOCK_STATUS_INITIALIZE").params.MANUAL, nil)
T.eq("online variable independent", variables.ONLINE, "1")
T.eq("valid battery", variables.BATTERY_PERCENT, "88")
T.eq("normal coarse battery", variables.LOW_BATTERY_STATE, "normal")
handoff("locked", true, 87, false)
T.eq("telemetry-only snapshots do not emit lock movement", count("LOCK_STATUS_CHANGED"), 0)
T.eq("telemetry still updates independently", variables.BATTERY_PERCENT, "87")
ReceivedFromProxy(5001, "UNLOCK")
T.eq("unlock goes through account binding", last("LOCK_INTENT").binding, 5002)
T.eq("explicit unlock intent", last("LOCK_INTENT").params.ACTION, "UNLOCK")
T.eq("command is scoped to current subscription", last("LOCK_INTENT").params.NONCE, nonce)
T.eq("request does not change reported bolt", variables.BOLT_STATE, "locked")
T.eq("request alone does not notify a successful movement", count("LOCK_STATUS_CHANGED"), 0)
handoff("locked", true, 87, false, "pending", "unlock")
handoff("unlocked", true, 87, false, "pending", "unlock")
T.eq("reported unlock emits a live native state change", last("LOCK_STATUS_CHANGED").params.LOCK_STATUS, "unlocked")
T.eq(
  "native change supplies the Last Action description",
  last("LOCK_STATUS_CHANGED").params.LAST_ACTION_DESCRIPTION,
  "Reported lock state: unlocked"
)
T.eq("native change uses a fixed public source", last("LOCK_STATUS_CHANGED").params.SOURCE, "Schlage Home")
T.eq(
  "matching pending Control4 action uses the commanded notification path",
  last("LOCK_STATUS_CHANGED").params.MANUAL,
  false
)
T.eq(
  "native update targets the lock proxy as a notification",
  { last("LOCK_STATUS_CHANGED").binding, last("LOCK_STATUS_CHANGED").kind },
  { 5001, "NOTIFY" }
)
local before = count("LOCK_STATUS_CHANGED")
handoff("unlocked", true, 87, false, "confirmed", "unlock")
T.eq("duplicate observed position produces no duplicate movement", count("LOCK_STATUS_CHANGED"), before)
OnBindingChanged(5001)
T.eq(
  "rebinding the native proxy initializes the current observed state",
  last("LOCK_STATUS_INITIALIZE").params.LOCK_STATUS,
  "unlocked"
)
T.eq("native proxy rebind creates no movement event", count("LOCK_STATUS_CHANGED"), before)
handoff("locked", true, 87, false, "confirmed", "unlock")
T.eq(
  "subsequent reported lock also emits a live native change",
  last("LOCK_STATUS_CHANGED").params.LOCK_STATUS,
  "locked"
)
T.eq(
  "outside change is not attributed to the previous confirmed command",
  last("LOCK_STATUS_CHANGED").params.MANUAL,
  true
)
handoff("unlocked", true, 87, false)
T.eq(
  "outside change with no pending action uses the external notification path",
  last("LOCK_STATUS_CHANGED").params.MANUAL,
  true
)
handoff("locked", true, 87, false, "pending", "lock")
T.eq("a later matching Control4 lock uses the commanded path", last("LOCK_STATUS_CHANGED").params.MANUAL, false)
handoff("unlocked", true, 87, false, "pending", "lock")
T.eq("observed opposite position is not claimed as the pending target", last("LOCK_STATUS_CHANGED").params.MANUAL, true)
handoff("locked", true, 87, false, "unconfirmed", "lock")
T.eq("expired command result cannot own a later observed change", last("LOCK_STATUS_CHANGED").params.MANUAL, true)
before = count("LOCK_INTENT")
ReceivedFromProxy(5002, "LOCK")
T.eq("wrong proxy binding is ignored", count("LOCK_INTENT"), before)
ReceivedFromProxy(5001, "LOCK")
T.eq("lock accepted", last("LOCK_INTENT").params.ACTION, "LOCK")
ReceivedFromProxy(5001, "TOGGLE")
T.eq("known toggle routed to authoritative account", last("LOCK_INTENT").params.ACTION, "TOGGLE")

T.section("Telemetry, disconnect, unknown and jam do not fabricate success")
local movement_count = count("LOCK_STATUS_CHANGED")
handoff("locked", false, 0, true)
T.eq("disconnect with unchanged position creates no movement event", count("LOCK_STATUS_CHANGED"), movement_count)
T.eq("disconnection with unchanged bolt is reported", last("ONLINE_CHANGED").params.STATE, false)
T.eq("disconnection does not move bolt", variables.BOLT_STATE, "locked")
T.eq("zero battery remains known", { variables.BATTERY_PERCENT, variables.BATTERY_KNOWN }, { "0", "1" })
before = count("LOCK_INTENT")
ReceivedFromProxy(5001, "UNLOCK")
T.eq("offline command does not leave driver", count("LOCK_INTENT"), before)
T.eq("offline outcome visible", variables.COMMAND_OUTCOME, "rejected: offline")
handoff("unknown", true)
T.eq(
  "missing battery is explicitly unknown",
  { variables.BATTERY_PERCENT, variables.BATTERY_KNOWN, variables.LOW_BATTERY_STATE },
  { "-1", "0", "unknown" }
)
T.eq("unknown bolt reports unknown proxy status", last("LOCK_STATUS_CHANGED").params.LOCK_STATUS, "unknown")
T.eq("unknown position is not labeled as an external movement", last("LOCK_STATUS_CHANGED").params.MANUAL, false)
before = count("LOCK_INTENT")
ReceivedFromProxy(5001, "TOGGLE")
T.eq("unknown-state toggle rejected", count("LOCK_INTENT"), before)
handoff("jammed", true)
T.eq("jam uses standard fault proxy status", last("LOCK_STATUS_CHANGED").params.LOCK_STATUS, "fault")
T.eq("fault is not labeled as an external locked/unlocked movement", last("LOCK_STATUS_CHANGED").params.MANUAL, false)
T.eq("jam available for programming", variables.JAMMED, "1")
T.excludes("raw cloud secrets never enter programming state", JSON:encode(variables), "sentinel")
provider = 0
OnBindingChanged(5002)
T.eq("unbinding immediately offline", variables.ONLINE, "0")
OnDriverDestroyed()
T.section("Properties dropdown selects and safely changes the physical lock")
C4:PersistDeleteValue("SchlageIdentity")
C4:PersistDeleteValue("SchlageSelection")
provider = 0
local direct, menus = {}, {}
function C4:SendToDevice(id, command, params)
  direct[#direct + 1] = { id = id, command = command, params = params }
end
function C4:UpdatePropertyList(name, choices, value)
  menus[name] = { choices = choices, value = value }
  Properties[name] = value
  OnPropertyChanged(name) -- exercise protection against property-update callbacks
end
local native_unbind = C4.Unbind
function C4:Unbind(...)
  provider = 0
  return native_unbind(self, ...)
end
local function sent(command)
  for i = #direct, 1, -1 do
    if direct[i].command == command then
      return direct[i].params
    end
  end
end
local function catalog_reply()
  ExecuteCommand("SCHLAGE_CATALOG", {
    SOURCE = "42",
    NONCE = sent("SCHLAGE_CATALOG_REQUEST").NONCE,
    JSON = JSON:encode({
      ready = true,
      scope = "menu-scope",
      devices = {
        { id = "front", name = "Front Door", available = true },
        { id = "garage", name = "Garage Door", available = true },
      },
    }),
  })
end
OnDriverInit()
OnDriverLateInit()
catalog_reply()
T.contains("available locks are actual Properties dropdown options", menus.Lock.choices, "Front Door,Garage Door")
T.eq("single account displayed automatically", menus["Schlage Account"].value, "42: Schlage Account")
Properties.Lock = "Front Door"
OnPropertyChanged("Lock")
catalog_reply()
local selected = sent("SCHLAGE_SELECT_LOCK")
T.eq("dropdown sends exact front-door selection", selected.ID, "front")
provider = 42
ExecuteCommand(
  "SCHLAGE_SELECTED",
  { SOURCE = "42", NONCE = selected.NONCE, ID = "front", SCOPE = "menu-scope", SUCCESS = "true" }
)
local function menu_snapshot(id)
  ExecuteCommand("SCHLAGE_SNAPSHOT", {
    SOURCE = "42",
    NONCE = last("REFRESH_STATE").params.NONCE,
    JSON = JSON:encode({
      id = id,
      scope = "menu-scope",
      sequence = 1,
      supported = true,
      connected = true,
      online = true,
      bolt = "locked",
    }),
  })
end
menu_snapshot("front")
T.eq("selected physical lock becomes online", variables.ONLINE, "1")
T.eq(
  "restart initializes the native proxy instead of replaying movement",
  last("LOCK_STATUS_INITIALIZE").params.LOCK_STATUS,
  "locked"
)
movement_count = count("LOCK_STATUS_CHANGED")
Properties.Lock = "Garage Door"
OnPropertyChanged("Lock")
T.truthy("changing selection releases old pending work", sent("SCHLAGE_RELEASE_LOCK"))
T.eq("changing selection immediately offline", variables.ONLINE, "0")
catalog_reply()
T.eq("new dropdown choice targets garage", sent("SCHLAGE_SELECT_LOCK").ID, "garage")
provider = 42
OnBindingChanged(5002)
menu_snapshot("front")
T.eq("old lock cannot reactivate companion after reselection", variables.ONLINE, "0")
menu_snapshot("garage")
T.eq("only selected new lock can restore online", variables.ONLINE, "1")
T.eq(
  "physical lock reassignment initializes its reported state",
  last("LOCK_STATUS_INITIALIZE").params.LOCK_STATUS,
  "locked"
)
T.eq("physical lock reassignment creates no movement event", count("LOCK_STATUS_CHANGED"), movement_count)
OnDriverDestroyed()
T.finish()
