require("c4_shim")
local T = require("testlib")
local Account = require("schlage.account")
local cfg = { pool_id = "synthetic-pool", client_id = "synthetic-client" }
local time, pending, timers, durable, writes = 100, {}, {}, {}, {}
local store = {
  get = function(_, key, default, encrypted)
    T.truthy("encrypted read " .. key, encrypted)
    return durable[key] or default
  end,
  set = function(_, key, value, encrypted)
    T.truthy("encrypted write " .. key, encrypted)
    local copy = {}
    for k, v in pairs(value) do
      copy[k] = v
    end
    durable[key] = copy
    writes[#writes + 1] = key
  end,
  delete = function(_, key)
    durable[key] = nil
  end,
}
local function call(mode, input, callback)
  local p = { mode = mode, input = input, callback = callback }
  pending[#pending + 1] = p
  return {
    cancel = function()
      p.cancelled = true
    end,
  }
end
local cognito = {
  login = function(_, username, password, callback)
    return call("login", { username = username, password = password }, callback)
  end,
  refresh = function(_, session, callback)
    return call("refresh", session, callback)
  end,
}
local function options()
  return {
    config = cfg,
    store = store,
    cognito = cognito,
    now = function()
      return time
    end,
    jitter = function()
      return 0.5
    end,
    schedule = function(seconds, fn)
      local t = { seconds = seconds, fn = fn }
      timers[#timers + 1] = t
      return {
        cancel = function()
          t.cancelled = true
        end,
      }
    end,
  }
end
local function session()
  return {
    username = "canonical",
    access_token = "synthetic-access",
    id_token = "synthetic-id",
    refresh_token = "synthetic-refresh",
    expires_at = time + 3600,
  }
end
T.section("Credential entry invalidates old sessions; clearing is not sign-out")
local a = Account.new(options())
a:start()
a:enter("username", "first@example.invalid")
a:enter("password", "synthetic-password")
a:enter("password", "")
T.eq("clearing retains encrypted password", durable.SchlageCredentials.password, "synthetic-password")
local completions = 0
local function done(value)
  if value then
    completions = completions + 1
  end
end
a:sign_in(done)
a:ensure(done)
a:sign_in(done)
T.eq("single concurrent login", #pending, 1)
pending[1].callback(session())
T.eq("all waiters notified", completions, 3)
T.eq("renew ahead of expiry", timers[#timers].seconds, 3540)
T.section("Concurrent renewal and restart use refresh, not stored password")
time = time + 3550
a:ensure(done)
a:ensure(done)
T.eq("single refresh", #pending, 2)
T.eq("uses refresh", pending[2].mode, "refresh")
pending[2].callback(session())
T.eq("refresh waiters", completions, 5)
a:destroy()
T.truthy("destroy preserves encrypted restart record", durable.SchlageSession)
local b = Account.new(options())
b:start()
T.eq("restart uses refresh", pending[3].mode, "refresh")
pending[3].callback(session())
T.eq("restart signed in", b.status, "signed_in")
T.section("Backoff, revoked tokens, and explicit reauthentication")
b:ensure(done, true)
pending[4].callback(nil, { category = "transient_error" })
T.eq("transient backoff", timers[#timers].seconds, 5)
b:ensure(function(_, err)
  T.eq("request held by cooldown", err.category, "backoff")
end)
T.eq("no extra refresh in cooldown", #pending, 4)
time = time + 5
timers[#timers].fn()
pending[5].callback(nil, { category = "rate_limited", retry_after = 91 })
T.eq("Retry-After respected", timers[#timers].seconds, 91)
time = time + 91
timers[#timers].fn()
pending[6].callback(nil, { category = "sign_in_required" })
T.eq("revoked status", b.status, "sign_in_required")
T.eq("revoked stored session deleted", durable.SchlageSession, nil)
b:ensure(function(_, err)
  T.eq("no implicit password login", err.category, "sign_in_required")
end)
T.eq("stopped automatic auth", #pending, 6)
T.section("Account replacement, late callbacks, sign-out, and destruction")
b:sign_in(done)
local old = pending[7]
b:enter("username", "second@example.invalid")
T.truthy("old request cancelled", old.cancelled)
T.eq("changing identity clears old password", durable.SchlageCredentials.password, nil)
old.callback(session())
T.eq("late auth cannot resurrect session", b.session, nil)
b:enter("password", "new-synthetic-password")
b:sign_in(done)
local late = pending[8]
b:sign_out()
late.callback(session())
T.eq("sign-out clears tokens", durable.SchlageSession, nil)
T.eq("sign-out clears credentials", durable.SchlageCredentials, nil)
T.eq("sign-out status", b.status, "signed_out")
b:enter("username", "third@example.invalid")
b:enter("password", "third-synthetic")
b:sign_in(done)
local destroyed = pending[9]
b:destroy()
destroyed.callback(session())
T.eq("destroyed callback cannot revive session", b.session, nil)
T.eq("destroyed credentials released", next(b.credentials), nil)
T.finish()
