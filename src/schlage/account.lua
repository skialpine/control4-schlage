-- One protected account session and one authentication flight per driver instance.
local Account = {}
Account.__index = Account
local CREDENTIALS, SESSION = "SchlageCredentials", "SchlageSession"
local terminal = {
  sign_in_required = true,
  unsupported_challenge = true,
  invalid_challenge = true,
  crypto_unavailable = true,
  crypto_budget_exceeded = true,
}

function Account.new(options)
  local self = setmetatable({
    store = options.store,
    cognito = options.cognito,
    config = options.config,
    schedule = options.schedule,
    now = options.now or os.time,
    jitter = options.jitter or math.random,
    on_status = options.on_status or function() end,
    on_ready = options.on_ready or function() end,
    on_refreshed = options.on_refreshed or function() end,
    on_invalidate = options.on_invalidate or function() end,
    generation = 0,
    attempts = 0,
    destroyed = false,
  }, Account)
  self.credentials = self.store:get(CREDENTIALS, {}, true)
  if type(self.credentials) ~= "table" then
    self.credentials = {}
  end
  local saved = self.store:get(SESSION, nil, true)
  if
    type(saved) == "table"
    and saved.schema == 1
    and saved.pool_id == self.config.pool_id
    and saved.client_id == self.config.client_id
    and saved.account_username == self.credentials.username
    and type(saved.refresh_token) == "string"
    and saved.refresh_token ~= ""
    and type(saved.username) == "string"
    and type(saved.expires_at) == "number"
  then
    self.session = saved
  end
  return self
end

function Account:credential_status()
  local username, password = self.credentials.username, self.credentials.password
  local has_username = type(username) == "string" and username ~= ""
  local has_password = type(password) == "string" and password ~= ""
  if has_username and has_password then
    local domain = username:match("^[^@]+@([%w%.%-]+)$")
    local initial = username:sub(1, 1):match("[%w]") or "*"
    local masked = domain and (initial .. "***@" .. domain:sub(1, 50)) or "***"
    return "Saved for " .. masked
  elseif has_username then
    return "Email saved; enter password"
  elseif has_password then
    return "Password saved; enter email"
  end
  return "Not configured"
end

function Account:_status(value)
  self.status = value
  self.on_status(value)
end

function Account:_cancel_timer()
  if self.timer then
    self.timer.cancel()
    self.timer = nil
  end
end

function Account:_invalidate()
  self.changing = true
  self.generation = self.generation + 1
  self:_cancel_timer()
  local old = self.job
  self.job = nil
  self.session, self.retry_at, self.attempts = nil, nil, 0
  if old then
    if old.handle then
      old.handle.cancel()
    end
    for _, callback in ipairs(old.waiters) do
      callback(nil, { category = "cancelled" })
    end
  end
  self.on_invalidate()
  self.changing = false
end

function Account:enter(field, value)
  if
    self.destroyed
    or self.changing
    or (field ~= "username" and field ~= "password")
    or type(value) ~= "string"
    or value == ""
  then
    return
  end
  self:_invalidate()
  self.store:delete(SESSION)
  if field == "username" and value ~= self.credentials.username then
    self.credentials = { username = value }
  else
    self.credentials[field] = value
  end
  self.store:set(CREDENTIALS, self.credentials, true)
  self:_status("sign_in_required")
end

function Account:_later(seconds, callback)
  self:_cancel_timer()
  local generation = self.generation
  self.timer = self.schedule(seconds, function()
    self.timer = nil
    if not self.destroyed and generation == self.generation then
      callback()
    end
  end)
end

function Account:_begin(mode, callback)
  if self.job then
    if callback then
      self.job.waiters[#self.job.waiters + 1] = callback
    end
    return
  end
  local job = { generation = self.generation, waiters = callback and { callback } or {}, mode = mode }
  self.job = job
  self:_cancel_timer()
  self:_status(mode == "login" and "signing_in" or "renewing")
  local function complete(session, err)
    if self.destroyed or self.job ~= job or self.generation ~= job.generation then
      return
    end
    self.job = nil
    if session then
      session.schema, session.pool_id, session.client_id = 1, self.config.pool_id, self.config.client_id
      session.account_username = self.credentials.username
      self.session, self.retry_at, self.attempts = session, nil, 0
      self.store:set(SESSION, session, true)
      self:_status("signed_in")
      self:_later(math.max(1, session.expires_at - self.now() - 60), function()
        self:_begin("refresh")
      end)
      if mode == "refresh" then
        self.on_refreshed(self.now())
      end
      for _, waiter in ipairs(job.waiters) do
        waiter(session)
      end
      if not self.destroyed and job.generation == self.generation then
        self.on_ready()
      end
    else
      err = err or { category = "transient_error" }
      if terminal[err.category] then
        self:_invalidate()
        self.store:delete(SESSION)
        self:_status(err.category)
      else
        self.attempts = math.min(self.attempts + 1, 7)
        local delay = math.max(5, math.min(300, 5 * 2 ^ (self.attempts - 1) * (0.8 + 0.4 * self.jitter())))
        if err.category == "rate_limited" then
          delay = err.retry_after or 60
        end
        delay = math.max(0, delay)
        self.retry_at = self.now() + delay
        self:_status("retry_wait")
        self:_later(delay, function()
          self:_begin(mode)
        end)
      end
      for _, waiter in ipairs(job.waiters) do
        waiter(nil, err)
      end
    end
  end
  if mode == "login" then
    job.handle = self.cognito:login(self.credentials.username, self.credentials.password, complete)
  else
    job.handle = self.cognito:refresh(self.session, complete)
  end
end

function Account:start()
  if self.destroyed then
    return
  end
  if self.session then
    -- Always renew after a controller/driver restart instead of trusting a cached access token.
    self:_begin("refresh")
  else
    self:_status("sign_in_required")
  end
end

function Account:sign_in(callback)
  callback = callback or function() end
  if self.destroyed or self.changing then
    callback(nil, { category = "cancelled" })
    return
  end
  if self.job then
    self.job.waiters[#self.job.waiters + 1] = callback
    return
  end
  if self.retry_at and self.now() < self.retry_at then
    callback(nil, { category = "backoff" })
    return
  end
  if
    type(self.credentials.username) ~= "string"
    or self.credentials.username == ""
    or type(self.credentials.password) ~= "string"
    or self.credentials.password == ""
  then
    self:_status("credentials_required")
    callback(nil, { category = "credentials_required" })
    return
  end
  self:_invalidate()
  self.store:delete(SESSION)
  self:_begin("login", callback)
end

function Account:ensure(callback, force)
  if self.destroyed or self.changing then
    callback(nil, { category = "cancelled" })
    return
  end
  if self.job then
    self.job.waiters[#self.job.waiters + 1] = callback
    return
  end
  if self.retry_at and self.now() < self.retry_at then
    callback(nil, { category = "backoff" })
    return
  end
  if not self.session then
    callback(nil, { category = "sign_in_required" })
    return
  end
  if not force and self.session.expires_at > self.now() + 60 then
    callback(self.session)
    return
  end
  self:_begin("refresh", callback)
end

function Account:sign_out()
  if self.destroyed then
    return
  end
  self:_invalidate()
  self.credentials = {}
  self.store:delete(SESSION)
  self.store:delete(CREDENTIALS)
  self:_status("signed_out")
end

function Account:destroy()
  self.destroyed = true
  self:_invalidate()
  self.credentials = {}
end

return Account
