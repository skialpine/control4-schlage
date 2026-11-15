-- The project policy applies before shared HTTP runs, even if HTTP was loaded
-- first. Upstream's standalone tests still cover its opt-in raw Ultra behavior.
require("c4_shim")
local T = require("testlib")
local http = require("lib.http")
local log = require("lib.logging")
local redact = require("schlage.log_policy")
-- Stop at the URL boundary: exercise shared HTTP logging with no real network.
urlDo = function(_, _, _, _, callback)
  callback(nil, 200, {}, {})
end
local lines = {}
function C4:DebugLog(line)
  lines[#lines + 1] = line
end
local native_print = print
print = function(line)
  lines[#lines + 1] = tostring(line)
end
local secret = {
  password = "POLICY_PASSWORD_SENTINEL",
  pin = "POLICY_PIN_SENTINEL",
  accessCode = "POLICY_CODE_SENTINEL",
  sessionId = "POLICY_SESSION_SENTINEL",
  access_token = "POLICY_TOKEN_SENTINEL",
}
for _, level in ipairs({ "5 - Trace", "6 - Ultra" }) do
  log:setLogLevel(level)
  log:setLogMode("Print and Log")
  -- As in the drivers, raw C4 dump switches must also remain disabled.
  require("schlage.transport").quiet()
  http:post("https://example.invalid/?token=POLICY_QUERY_SENTINEL", secret, {
    Authorization = "Bearer POLICY_HEADER_SENTINEL",
  })
  T.eq("PIN remains masked at " .. level, redact.forLog(secret).pin, "***REDACTED***")
end
log:setLogMode("Off")
print = native_print
local output = table.concat(lines, "\n")
T.contains("shared HTTP actually logged the request", output, "Http:request(POST")
T.contains("redaction markers are present", output, "***REDACTED***")
for key, value in pairs(secret) do
  T.excludes("shared HTTP masks " .. key, output, value)
end
T.excludes("shared HTTP masks the authorization header", output, "POLICY_HEADER_SENTINEL")
T.excludes("shared HTTP masks the URL token", output, "POLICY_QUERY_SENTINEL")
T.eq("redaction does not mutate the request body", secret.pin, "POLICY_PIN_SENTINEL")
T.finish()
