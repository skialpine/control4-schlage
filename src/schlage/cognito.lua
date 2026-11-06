local SRP = require("schlage.cognito_srp")
local Cognito = {}
Cognito.__index = Cognito

function Cognito.new(options)
  return setmetatable({
    config = options.config,
    transport = options.transport,
    now = options.now or os.time,
    milliseconds = options.milliseconds or function()
      return C4:GetTime()
    end,
    srp = options.srp or SRP,
    metric = options.metric or function() end,
  }, Cognito)
end

local function operation(callback)
  local op = { handles = {}, done = false }
  function op:finish(value, err)
    if self.done then
      return
    end
    self.done = true
    if self.srp then
      self.srp:clear()
      self.srp = nil
    end
    self.handles = {}
    callback(value, err)
  end
  function op:add(handle)
    if not handle then
      return
    end
    if self.done then
      handle.cancel()
    else
      self.handles[#self.handles + 1] = handle
    end
  end
  function op.cancel()
    if op.done then
      return
    end
    op.done = true
    if op.srp then
      op.srp:clear()
      op.srp = nil
    end
    for _, handle in ipairs(op.handles) do
      handle.cancel()
    end
    op.handles = {}
  end
  return op
end

local function normalize(data, previous, username, now)
  local a = type(data) == "table" and data.AuthenticationResult
  if type(a) ~= "table" then
    return nil, { category = data and data.ChallengeName and "unsupported_challenge" or "malformed_response" }
  end
  local expiry = tonumber(a.ExpiresIn)
  local refresh = a.RefreshToken or (previous and previous.refresh_token)
  if
    type(a.AccessToken) ~= "string"
    or a.AccessToken == ""
    or type(a.IdToken) ~= "string"
    or a.IdToken == ""
    or type(refresh) ~= "string"
    or refresh == ""
    or not expiry
    or expiry < 120
    or expiry > 86400
    or (a.TokenType and (type(a.TokenType) ~= "string" or a.TokenType:lower() ~= "bearer"))
  then
    return nil, { category = "malformed_response" }
  end
  return {
    access_token = a.AccessToken,
    id_token = a.IdToken,
    refresh_token = refresh,
    expires_at = now + expiry,
    username = username,
  }
end

function Cognito:login(username, password, callback)
  local op = operation(callback)
  local start = self.milliseconds()
  local ok, session = pcall(self.srp.new, self.config, username, password)
  password = nil
  local elapsed = self.milliseconds() - start
  self.metric("srp_public_ms", elapsed)
  if not ok then
    op:finish(nil, { category = "crypto_unavailable" })
    return op
  end
  op.srp = session
  if elapsed > self.config.crypto_budget_ms then
    op:finish(nil, { category = "crypto_budget_exceeded" })
    return op
  end
  op:add(self.transport:cognito("InitiateAuth", {
    ClientId = self.config.client_id,
    AuthFlow = "USER_SRP_AUTH",
    AuthParameters = session:parameters(),
  }, function(data, err)
    if op.done then
      return
    end
    if err then
      op:finish(nil, err)
      return
    end
    if data.ChallengeName ~= "PASSWORD_VERIFIER" then
      op:finish(nil, { category = "unsupported_challenge" })
      return
    end
    if type(data.ChallengeParameters) ~= "table" then
      op:finish(nil, { category = "malformed_response" })
      return
    end
    local issued = self.milliseconds()
    local calculated, response, canonical = pcall(session.respond, session, data.ChallengeParameters, self.now())
    local duration = self.milliseconds() - issued
    self.metric("srp_proof_ms", duration)
    if not calculated then
      op:finish(nil, { category = "invalid_challenge" })
      return
    end
    if duration > self.config.crypto_budget_ms then
      op:finish(nil, { category = "crypto_budget_exceeded" })
      return
    end
    local request =
      { ClientId = self.config.client_id, ChallengeName = "PASSWORD_VERIFIER", ChallengeResponses = response }
    if data.Session then
      request.Session = data.Session
    end
    op:add(self.transport:cognito("RespondToAuthChallenge", request, function(tokens, failure)
      if op.done then
        return
      end
      if failure then
        op:finish(nil, failure)
        return
      end
      local value, invalid = normalize(tokens, nil, canonical, self.now())
      op:finish(value, invalid)
    end))
  end))
  return op
end

function Cognito:refresh(session, callback)
  local op = operation(callback)
  local parameters =
    { REFRESH_TOKEN = session.refresh_token, SECRET_HASH = self.srp.secret_hash(session.username, self.config) }
  op:add(self.transport:cognito("InitiateAuth", {
    ClientId = self.config.client_id,
    AuthFlow = "REFRESH_TOKEN_AUTH",
    AuthParameters = parameters,
  }, function(data, err)
    if op.done then
      return
    end
    if err then
      op:finish(nil, err)
      return
    end
    local value, invalid = normalize(data, session, session.username, self.now())
    op:finish(value, invalid)
  end))
  return op
end

return Cognito
