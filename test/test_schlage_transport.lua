require("c4_shim")
local T = require("testlib")
local Transport = require("schlage.transport")
local JSON = require("JSON")
local config = require("schlage.config")
local transport = Transport.new(config)
local call, answer, failure
urlDo = function(method, url, data, headers, callback, _, options)
  call = { method = method, url = url, data = data, headers = headers, callback = callback, options = options }
  return {
    Cancel = function()
      call.cancelled = true
    end,
  }
end
local function result(a, b)
  answer, failure = a, b
end
T.section("Exact protocol headers and TLS options")
DEBUGPRINT, DEBUG_URL = true, true
transport:cognito("InitiateAuth", { AuthParameters = { PASSWORD = "sentinel-password" } }, result)
T.eq("Cognito content type preserved", call.headers["Content-Type"], "application/x-amz-json-1.1")
T.eq("AWS action", call.headers["X-Amz-Target"], "AWSCognitoIdentityProviderService.InitiateAuth")
T.eq("certificate/hostname verification", call.options.ssl_verify_host, true)
T.eq("cookies disabled", call.options.cookies_enable, false)
T.falsy("raw tracing disabled", DEBUG_URL)
T.falsy("handler tracing disabled", DEBUGPRINT)
call.callback(nil, 200, {}, '{"ChallengeName":"PASSWORD_VERIFIER"}')
T.eq("valid JSON", answer.ChallengeName, "PASSWORD_VERIFIER")
transport:devices("sentinel-token", result)
T.eq("read-only discovery method", call.method, "GET")
T.eq("discovery route", call.url, config.api_url .. "/devices?archetype=lock")
T.eq("access token header", call.headers.Authorization, "Bearer sentinel-token")
T.eq("API key", call.headers["X-Api-Key"], config.api_key)
T.section("Malformed, permanent, unauthorized, rate-limited, and network failures")
transport:write("sentinel-token", "synthetic/id?x", false, result)
T.eq("explicit mutation method", call.method, "PUT")
T.eq("device ID encoded as one path segment", call.url, config.api_url .. "/devices/synthetic%2Fid%3Fx")
T.eq("JSON content type", call.headers["Content-Type"], "application/json")
T.eq("unlock body has no unrelated attributes", JSON:decode(call.data), { attributes = { lockState = 0 } })
call.callback(nil, 204, {}, "")
T.eq("empty 204 accepted without inferring physical state", failure, nil)
transport:write("sentinel-token", "synthetic-id", true, result)
T.eq("explicit lock body", JSON:decode(call.data), { attributes = { lockState = 1 } })
T.raises("non-boolean write intent is refused", function()
  transport:write("synthetic", "id", "toggle", result)
end)
transport:device("synthetic", "id", result)
T.eq("individual read uses GET", call.method, "GET")
T.eq("individual read route", call.url, config.api_url .. "/devices/id")
for _, case in ipairs({
  { nil, 200, {}, "invalid-json", "malformed_response" },
  { nil, 400, {}, '{"__type":"aws#NotAuthorizedException","message":"sentinel-password"}', "sign_in_required" },
  { nil, 401, {}, "{}", "unauthorized" },
  { nil, 429, { ["Retry-After"] = "73" }, "{}", "rate_limited" },
  { nil, 503, {}, "{}", "transient_error" },
  { "sentinel-private-error", 0, {}, "", "transport_error" },
}) do
  transport:devices("sentinel-token", result)
  call.callback(case[1], case[2], case[3], case[4])
  T.eq(case[5], failure.category, case[5])
  T.eq("raw failure body not returned", failure.body, nil)
  if case[2] == 429 then
    T.eq("rate delay", failure.retry_after, 73)
  end
end
local count = 0
local handle = transport:devices("sentinel-token", function()
  count = count + 1
end)
handle.cancel()
call.callback(nil, 200, {}, "[]")
T.eq("cancelled callback ignored", count, 0)
T.truthy("transfer cancelled", call.cancelled)
T.finish()
