require("c4_shim")
local T = require("testlib")
local properties, requests, lines = {}, {}, {}
local battery_events = {}
function C4:FireEventByID(id)
  local event = require("lib.events"):getEvents().schlage_account.daily_low_battery
  if id == event.eventId then
    battery_events[#battery_events + 1] = Variables.BATTERY_ALERT_MESSAGE
  end
end
Properties =
  { ["Log Level"] = "6 - Ultra", ["Log Mode"] = "Print and Log", ["Schlage Email"] = "", ["Schlage Password"] = "" }
function C4:UpdateProperty(name, value)
  Properties[name] = value
  properties[name] = value
end
function C4:GetTime()
  return 1000
end
function C4:GetTickCount()
  return 1000
end
function C4:GetDevicesByC4iName()
  return {}
end
function C4:RoomGetId()
  return 1
end
function C4:DebugLog(line)
  lines[#lines + 1] = tostring(line)
end
local tokens = {
  "SENTINEL-email@example.invalid",
  "SENTINEL-password",
  "SENTINEL-access",
  "SENTINEL-id",
  "SENTINEL-refresh",
  "SENTINEL-CAT",
  "SENTINEL-SAT",
  "SENTINEL-PIN",
  "SENTINEL-SRP-private",
  "SENTINEL-web-identity",
}
local JSON = require("JSON")
local f = assert(io.open("test/fixtures/schlage/cognito-vectors.json"))
local vectors = JSON:decode(f:read("*a"))
f:close()
local function enter(name, value)
  Properties[name] = value
  OnPropertyChanged(name)
end
local ok, err, output = T.capture(function()
  dofile("drivers/schlage_account/driver.lua")
  OnDriverInit()
  OnDriverLateInit()
  local function quiet(label)
    T.falsy(label, DEBUGPRINT or DEBUG_URL or DEBUG_RFN or DEBUG_WEBSOCKET or DEBUG_TIMER)
  end
  quiet("Ultra startup never enables raw protocol or callback dumps")
  for _, mode in ipairs({ "Off", "Print", "Log", "Print and Log" }) do
    enter("Log Mode", mode)
    enter("Log Level", "3 - Info")
    enter("Log Level", "6 - Ultra")
    quiet("Ultra setting changes keep raw dumps off: " .. mode)
  end
  T.eq("structured Ultra logging remains available", require("lib.logging"):getLogLevel(), 6)
  -- Install at the shared URL boundary: no real account or network is used.
  urlDo = function(method, url, data, headers, callback, _, options)
    requests[#requests + 1] =
      { method = method, url = url, data = data, headers = headers, callback = callback, options = options }
    return { Cancel = function() end }
  end
  T.eq("no saved credentials initially", properties["Credentials"], "Not configured")
  enter("Schlage Email", tokens[1])
  T.eq("email entry acknowledged", properties["Credentials"], "Email saved; enter password")
  enter("Schlage Password", tokens[2])
  T.eq("saved indicator uses masked account", properties["Credentials"], "Saved for S***@example.invalid")
  T.excludes("indicator omits full email", properties["Credentials"], tokens[1])
  T.eq("email property cleared", properties["Schlage Email"], "")
  T.eq("password property cleared", properties["Schlage Password"], "")
  T.excludes(
    "plain persistence does not contain credentials",
    C4:PersistGetValue("SchlageCredentials", false),
    tokens[2]
  )
  ExecuteCommand("LUA_ACTION", { ACTION = "Sign_In" })
  T.eq("one sign-in request", #requests, 1)
  requests[1].callback(
    nil,
    200,
    {},
    { ChallengeName = "PASSWORD_VERIFIER", ChallengeParameters = vectors.vectors[1].challenge }
  )
  T.eq("proof request", #requests, 2)
  requests[2].callback(nil, 200, {}, {
    AuthenticationResult = {
      AccessToken = tokens[3],
      IdToken = tokens[4],
      RefreshToken = tokens[5],
      ExpiresIn = 3600,
    },
  })
  T.eq("automatic read-only discovery after sign-in", requests[3].method, "GET")
  T.eq("login does not masquerade as token renewal", properties["Last Session Renewal"], "Not yet observed")
  requests[3].callback(
    nil,
    200,
    {},
    JSON:newArray({
      {
        deviceId = "synthetic-1",
        devicetypeId = "be499wifi",
        CAT = tokens[6],
        SAT = tokens[7],
        attributes = {
          PIN = tokens[8],
        },
      },
    })
  )
  T.eq("automatic discovery keeps the property compact", properties["Discovered Locks"], "1 lock found")
  local found_binding = false
  for _, namespace in pairs(require("lib.bindings"):getBindings()) do
    if namespace["synthetic-1"] then
      found_binding = true
    end
  end
  T.truthy("automatic discovery creates a stable connection", found_binding)
  Properties["Log Mode"] = "Off"
  OnPropertyChanged("Log Mode")
  for _, count in ipairs({ 0, 1, 6 }) do
    local devices = JSON:newArray({})
    for i = 1, count do
      devices[i] = {
        deviceId = "synthetic-" .. i,
        name = "Test lock " .. i,
        devicetypeId = "be499wifi",
        modelName = "BE499WB",
        CAT = tokens[6],
        SAT = tokens[7],
        attributes = { PIN = tokens[8], token = tokens[3] },
      }
    end
    local printed, failure, listing = T.capture(function()
      ExecuteCommand("LUA_ACTION", { ACTION = "Discover_Locks" })
      requests[#requests].callback(nil, 200, {}, devices)
    end)
    T.truthy("manual discovery succeeds with Log Mode Off", printed, failure)
    T.eq(
      "count stays compact",
      properties["Discovered Locks"],
      count .. (count == 1 and " lock found" or " locks found")
    )
    T.contains("Lua output has count", listing, "Schlage discovery: " .. properties["Discovered Locks"])
    for i = 1, count do
      T.contains(
        "each lock has its own Lua row",
        listing,
        i .. ". Test lock " .. i .. " | type=be499wifi | model=BE499WB"
      )
    end
    for _, secret in ipairs(tokens) do
      T.excludes("listing contains no secret", listing, secret)
    end
    T.excludes("listing omits cloud identifiers", listing, "synthetic-")
  end
  T.eq("normal or missing battery data creates no daily events", #battery_events, 0)
  enter("Battery Alert Time", "00:00")
  local function battery_snapshot()
    ExecuteCommand("Discover_Locks")
    requests[#requests].callback(
      nil,
      200,
      {},
      JSON:newArray({
        {
          deviceId = "low-a",
          name = "Patio",
          devicetypeId = "be499wifi",
          connected = true,
          attributes = { lockState = 1, batteryLevel = 20, batteryLowState = 0 },
        },
        {
          deviceId = "low-b",
          name = "Garage",
          devicetypeId = "be499wifi",
          connected = true,
          attributes = { lockState = 0, batteryLevel = 80, batteryLowState = 1 },
        },
        {
          deviceId = "offline",
          name = "Offline",
          devicetypeId = "be499wifi",
          connected = false,
          attributes = { batteryLevel = 1, batteryLowState = 1 },
        },
        {
          deviceId = "unsupported",
          name = "Unsupported",
          devicetypeId = "future-lock",
          connected = true,
          attributes = { batteryLevel = 1, batteryLowState = 1 },
        },
      })
    )
  end
  battery_snapshot()
  T.eq("account emits events for all qualifying locks without companions", #battery_events, 2)
  local emitted = table.concat(battery_events, " ")
  T.contains("daily message names first lock", emitted, "Patio (20%)")
  T.contains("daily message names second lock", emitted, "Garage (80%)")
  T.excludes("no daily message for offline lock", emitted, "Offline")
  T.excludes("no daily message for unsupported lock", emitted, "Unsupported")
  battery_snapshot()
  T.eq("repeat discovery cannot duplicate daily account events", #battery_events, 2)
  ExecuteCommand("Test_Battery_Alert")
  T.eq("account test action emits a separate event", #battery_events, 3)
  T.contains("account test message explicitly labeled", battery_events[3], "TEST:")
  battery_snapshot()
  T.eq("test does not reset the daily allowance", #battery_events, 3)
  Properties["Log Mode"] = "Print and Log"
  OnPropertyChanged("Log Mode")
  local redact = require("schlage.redact")
  local log = require("lib.logging")
  log:trace(
    "Sanitized diagnostic: %s",
    redact.value({
      CAT = tokens[6],
      SAT = tokens[7],
      nested = { a = tokens[9], PIN = tokens[8] },
      body = JSON:encode({ token = tokens[3] }),
      [tokens[10]] = "value",
    })
  )
  T.falsy("ultra never enables raw URL traces", DEBUG_URL)
  T.falsy("ultra never enables handler traces", DEBUGPRINT)
  Properties["Log Mode"] = "Off"
  OnPropertyChanged("Log Mode")
  local renewed, renewal_error, renewal_output = T.capture(function()
    ExecuteCommand("LUA_ACTION", { ACTION = "Renew_Session" })
    requests[#requests].callback(nil, 200, {}, {
      AuthenticationResult = { AccessToken = tokens[3], IdToken = tokens[4], ExpiresIn = 3600 },
    })
  end)
  T.truthy("renewal runs with logging off", renewed, renewal_error)
  T.contains("renewal start always visible", renewal_output, "Schlage session renewal requested.")
  T.contains("renewal completion always visible", renewal_output, "Schlage session renewal succeeded.")
  T.contains(
    "actual logging configuration visible",
    renewal_output,
    "mode=Off; level=6 - Ultra; print=false; log=false"
  )
  for _, secret in ipairs(tokens) do
    T.excludes("renewal action prints no secret", renewal_output, secret)
  end
  Properties["Log Mode"] = "Print and Log"
  OnPropertyChanged("Log Mode")
  T.eq(
    "successful renewal leaves a visible controller-local timestamp",
    properties["Last Session Renewal"],
    os.date("%Y-%m-%d %H:%M:%S %Z")
  )
  T.eq("renewed session returns to signed in", properties["Driver Status"], "signed_in")
  requests[#requests].callback(nil, 200, {}, JSON:newArray({}))
  local before_renewal = #requests
  ExecuteCommand("LUA_ACTION", { ACTION = "Renew_Session" })
  requests[#requests].callback(
    nil,
    400,
    {},
    JSON:encode({ __type = "NotAuthorizedException", message = table.concat(tokens, " ") })
  )
  T.eq("revoked refresh requires installer action", properties["Driver Status"], "sign_in_required")
  T.eq("no automatic password fallback", #requests, before_renewal + 1)
  ExecuteCommand("LUA_ACTION", { ACTION = "Sign_Out" })
  T.eq("sign-out status", properties["Driver Status"], "signed_out")
  T.eq("sign-out clears credential indicator", properties["Credentials"], "Not configured")
  T.eq("sign-out clears previous account renewal result", properties["Last Session Renewal"], "Not yet observed")
  T.eq("sign-out deletes stored token", C4:PersistGetValue("SchlageSession", true), nil)
  T.eq("sign-out deletes stored credentials", C4:PersistGetValue("SchlageCredentials", true), nil)
  OnDriverDestroyed()
end)
T.truthy("driver lifecycle runs", ok, err)
T.contains("renewal failure category visible", output, "Schlage session renewal failed: sign_in_required")
local all = output .. table.concat(lines, "\n")
T.excludes("driver response callbacks run without swallowed errors", all, "Schlage response handling failed")
for _, secret in ipairs(tokens) do
  T.excludes("no sentinel in print or C4 log", all, secret)
end
T.finish()
