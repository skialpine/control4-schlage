require("c4_shim")
local T = require("testlib")
local srp = require("schlage.cognito_srp")
local crypto = require("crypto")
local bytes = require("crypto.utils").bytes
local JSON = require("JSON")
local file = assert(io.open("test/fixtures/schlage/cognito-vectors.json", "r"))
local vectors = JSON:decode(file:read("*a"))
file:close()
T.section("Cognito signed integer padding and English UTC timestamp")
for _, p in ipairs(vectors.padding) do
  T.eq(p.input, srp.pad_hex(p.input), p.output)
end
T.eq("UTC format independent of locale", srp.timestamp(vectors.timestamp_epoch), vectors.vectors[1].timestamp)
T.section("Independent pycognito vectors through real accelerated Lua math")
for _, v in ipairs(vectors.vectors) do
  local s = srp.new(v.config, v.username, v.password, function()
    return bytes.from_hex(v.private_hex)
  end)
  T.eq(v.name .. " auth parameters", s:parameters(), v.auth_parameters)
  T.eq(v.name .. " SHA256/HKDF key", bytes.to_hex(s:derive(v.challenge)), v.key_hex)
  T.eq(
    v.name .. " challenge response and canonical username",
    s:respond(v.challenge, vectors.timestamp_epoch),
    v.response
  )
  T.eq("private exponent released", s.a, nil)
  T.eq("password released", s.password, nil)
end
T.section("Fail closed on unavailable crypto, entropy, and malformed server values")
local v = vectors.vectors[1]
T.raises("short entropy", function()
  srp.new(v.config, v.username, v.password, function()
    return "short"
  end)
end, "secure_entropy_failed")
T.raises("zero entropy", function()
  srp.new(v.config, v.username, v.password, function()
    return string.rep("\0", 128)
  end)
end, "secure_entropy_failed")
local s = srp.new(v.config, v.username, v.password)
local c = {}
for k, value in pairs(v.challenge) do
  c[k] = value
end
c.SRP_B = "0"
T.raises("zero B rejected", function()
  s:derive(c)
end, "invalid_srp_server_public")
local old = crypto.bignum.is_accelerated
crypto.bignum.is_accelerated = function()
  return false
end
T.raises("absent acceleration rejected", function()
  srp.new(v.config, v.username, v.password)
end, "native_crypto_unavailable")
crypto.bignum.is_accelerated = old
local available = crypto.random.available
crypto.random.available = function()
  return false
end
T.raises("absent CSPRNG rejected", function()
  srp.new(v.config, v.username, v.password)
end, "secure_entropy_unavailable")
crypto.random.available = available
local native = crypto.openssl_wrapper.get(crypto.openssl_wrapper.Feature.BN).bn
local native_power = native.powmod
local portable = crypto.bignum.mod_exp
native.powmod = function(base, exponent, modulus)
  if #native.tohex(modulus) > 700 then
    error("synthetic native operation failure")
  end
  return native_power(base, exponent, modulus)
end
crypto.bignum.mod_exp = function()
  error("portable fallback must not run")
end
T.raises("native operation failure never enters portable fallback", function()
  srp.new(v.config, v.username, v.password)
end, "native_crypto_failed")
native.powmod = native_power
crypto.bignum.mod_exp = portable
T.finish()
