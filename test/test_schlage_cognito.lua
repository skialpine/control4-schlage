require("c4_shim")
local T = require("testlib")
local Cognito = require("schlage.cognito")
local SRP = require("schlage.cognito_srp")
local JSON = require("JSON")
local f = assert(io.open("test/fixtures/schlage/cognito-vectors.json"))
local fixture = JSON:decode(f:read("*a"))
f:close()
local v = fixture.vectors[1]
local config = {}
for k, value in pairs(v.config) do
  config[k] = value
end
config.crypto_budget_ms = 250
local calls = {}
local transport = {
  cognito = function(_, action, request, callback)
    local call = { action = action, request = request, callback = callback, cancelled = false }
    calls[#calls + 1] = call
    return {
      cancel = function()
        call.cancelled = true
      end,
    }
  end,
}
local now, tick = fixture.timestamp_epoch, 0
local c = Cognito.new({
  config = config,
  transport = transport,
  now = function()
    return now
  end,
  milliseconds = function()
    return tick
  end,
})
local value, err
local function result(a, b)
  value, err = a, b
end
local tokens = {
  AuthenticationResult = {
    AccessToken = "synthetic-access",
    IdToken = "synthetic-id",
    RefreshToken = "synthetic-refresh",
    ExpiresIn = 3600,
    TokenType = "Bearer",
  },
}
T.section("Native asynchronous USER_SRP_AUTH and PASSWORD_VERIFIER")
c:login(v.username, v.password, result)
T.eq("SRP flow", calls[1].request.AuthFlow, "USER_SRP_AUTH")
calls[1].callback({
  ChallengeName = "PASSWORD_VERIFIER",
  ChallengeParameters = v.challenge,
  Session = "synthetic-challenge-session",
})
T.eq("challenge target", calls[2].action, "RespondToAuthChallenge")
T.eq("session passed unchanged", calls[2].request.Session, "synthetic-challenge-session")
T.eq("canonical response username", calls[2].request.ChallengeResponses.USERNAME, v.challenge.USERNAME)
calls[2].callback(tokens)
T.eq("login succeeds", err, nil)
T.eq("expiry", value.expires_at, now + 3600)
T.eq("canonical identity persisted for refresh hash", value.username, v.challenge.USERNAME)
local previous = value
T.section("Renewal preserves refresh token when omitted")
c:refresh(previous, result)
T.eq("refresh flow", calls[3].request.AuthFlow, "REFRESH_TOKEN_AUTH")
T.eq("canonical refresh hash", calls[3].request.AuthParameters.SECRET_HASH, SRP.secret_hash(previous.username, config))
local replacement = { AuthenticationResult = { AccessToken = "new-access", IdToken = "new-id", ExpiresIn = 3600 } }
calls[3].callback(replacement)
T.eq("refresh preserved", value.refresh_token, previous.refresh_token)
T.section("Permanent, unsupported, malformed, transient, and cancellation paths")
c:login(v.username, v.password, result)
calls[4].callback(nil, { category = "sign_in_required" })
T.eq("invalid credentials", err.category, "sign_in_required")
c:login(v.username, v.password, result)
calls[5].callback({ ChallengeName = "SMS_MFA" })
T.eq("unsupported challenge", err.category, "unsupported_challenge")
c:login(v.username, v.password, result)
calls[6].callback(nil, { category = "transient_error" })
T.eq("transient", err.category, "transient_error")
c:refresh(previous, result)
calls[7].callback(nil, { category = "sign_in_required" })
T.eq("revoked refresh", err.category, "sign_in_required")
c:refresh(previous, result)
calls[8].callback({ AuthenticationResult = {} })
T.eq("malformed tokens", err.category, "malformed_response")
local count = 0
local op = c:login(v.username, v.password, function()
  count = count + 1
end)
op.cancel()
calls[9].callback({ ChallengeName = "PASSWORD_VERIFIER", ChallengeParameters = v.challenge })
T.eq("late challenge ignored", #calls, 9)
T.eq("cancel suppresses callback", count, 0)
T.truthy("network cancelled", calls[9].cancelled)
T.finish()
