-- Cognito's SRP variant. Protocol reference: pinned pycognito (Apache-2.0).
-- See docs/reference-revisions.json and licenses/pycognito-LICENSE.
local crypto = require("crypto")
local bn = crypto.bignum
local bytes = require("crypto.utils").bytes
local sha = crypto.sha256
local M = {}
local Session = {}
Session.__index = Session
local N = bn.from_hex(crypto.srp.GROUP_3072.N)
local G = bn.from_number(2) -- Cognito uses g=2, not generic SRP's g=5.

local function hex(n)
  return (bn.to_hex(n):gsub("^0+", ""):lower()):gsub("^$", "0")
end

function M.pad_hex(h)
  assert(type(h) == "string" and h:match("^%x+$"), "invalid_srp_integer")
  if #h % 2 == 1 then
    return "0" .. h
  elseif h:sub(1, 1):match("[89a-fA-F]") then
    return "00" .. h
  end
  return h
end

local function padded(n)
  return bytes.from_hex(M.pad_hex(hex(n)))
end

function M.ready()
  crypto.use_openssl(true)
  local accelerated = bn.is_accelerated("mod_exp")
  if not accelerated then
    return false, "native_crypto_unavailable"
  end
  if not crypto.random.available() then
    return false, "secure_entropy_unavailable"
  end
  return true
end

-- Use the checked OpenSSL primitive directly: the general-purpose bignum helper
-- can fall back to pure Lua on an operation failure, which would block Director.
local function power(base, exponent)
  assert(bn.is_accelerated("mod_exp"), "native_crypto_unavailable")
  local lib = crypto.openssl_wrapper.get(crypto.openssl_wrapper.Feature.BN).bn
  local pow = lib.powmod or lib.mod_exp
  local ok, result = pcall(function()
    local raw = pow(lib.text(bn.to_bytes(base)), lib.text(bn.to_bytes(exponent)), lib.text(bn.to_bytes(N)))
    local value = lib.tohex(raw)
    assert(type(value) == "string" and value:match("^%x+$"))
    return bn.from_hex(value)
  end)
  assert(ok, "native_crypto_failed")
  return result
end

function M.timestamp(epoch)
  local t = os.date("!*t", epoch)
  local days = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
  local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
  return string.format(
    "%s %s %d %02d:%02d:%02d UTC %d",
    days[t.wday],
    months[t.month],
    t.day,
    t.hour,
    t.min,
    t.sec,
    t.year
  )
end

function M.secret_hash(username, config)
  return C4:Base64Encode(sha.hmac_sha256(config.client_secret, username .. config.client_id))
end

function M.new(config, username, password, draw)
  local ready, reason = M.ready()
  assert(ready, reason)
  assert(
    type(username) == "string" and username ~= "" and type(password) == "string" and password ~= "",
    "credentials_required"
  )
  local raw = (draw or crypto.random.bytes)(128)
  assert(type(raw) == "string" and #raw == 128, "secure_entropy_failed")
  local a = bn.mod(bn.from_bytes(raw), N)
  assert(not bn.is_zero(a), "secure_entropy_failed")
  local A = power(G, a)
  assert(not bn.is_zero(bn.mod(A, N)), "invalid_srp_public")
  return setmetatable({ config = config, username = username, password = password, a = a, A = A }, Session)
end

function Session:parameters()
  return { USERNAME = self.username, SRP_A = hex(self.A), SECRET_HASH = M.secret_hash(self.username, self.config) }
end

function Session:derive(challenge)
  local b, salt, username = challenge.SRP_B, challenge.SALT, challenge.USER_ID_FOR_SRP
  assert(type(b) == "string" and #b <= 770 and b:match("^%x+$"), "invalid_srp_challenge")
  assert(type(salt) == "string" and #salt <= 128 and salt:match("^%x+$"), "invalid_srp_challenge")
  assert(type(username) == "string" and username ~= "" and #username <= 256, "invalid_srp_challenge")
  local B = bn.from_hex(b)
  assert(not bn.is_zero(bn.mod(B, N)), "invalid_srp_server_public")
  local u = bn.from_bytes(sha.sha256(padded(self.A) .. padded(B)))
  assert(not bn.is_zero(u), "invalid_srp_scrambler")
  local pool = assert(self.config.pool_id:match("^[^_]+_(.+)$"), "invalid_pool")
  local identity = sha.sha256(pool .. username .. ":" .. self.password)
  local x = bn.from_bytes(sha.sha256(bytes.from_hex(M.pad_hex(salt)) .. identity))
  local k = bn.from_bytes(sha.sha256(padded(N) .. padded(G)))
  local base = bn.mod_sub(B, bn.mod_mul(k, power(G, x), N), N)
  local S = power(base, bn.add(self.a, bn.mul(u, x)))
  assert(not bn.is_zero(S), "invalid_srp_shared_secret")
  return crypto.hkdf.hkdf_sha256(padded(u), padded(S), "Caldera Derived Key", 16)
end

function Session:respond(challenge, epoch)
  local key = self:derive(challenge)
  local block = challenge.SECRET_BLOCK
  assert(
    type(block) == "string" and #block <= 16384 and #block % 4 == 0 and block:match("^[%w+/=]+$"),
    "invalid_srp_secret_block"
  )
  local username = challenge.USERNAME or self.username
  assert(type(username) == "string" and username ~= "" and #username <= 256, "invalid_srp_username")
  local timestamp = M.timestamp(epoch)
  local pool = self.config.pool_id:match("^[^_]+_(.+)$")
  local message = pool .. challenge.USER_ID_FOR_SRP .. C4:Base64Decode(block) .. timestamp
  local response = {
    USERNAME = username,
    TIMESTAMP = timestamp,
    PASSWORD_CLAIM_SECRET_BLOCK = block,
    PASSWORD_CLAIM_SIGNATURE = C4:Base64Encode(sha.hmac_sha256(key, message)),
    SECRET_HASH = M.secret_hash(username, self.config),
  }
  self:clear()
  return response, username
end

function Session:clear()
  self.password, self.a, self.A = nil, nil, nil
end

return M
