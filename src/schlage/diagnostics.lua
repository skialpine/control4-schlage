-- Local, allowlisted diagnostics. Never accept an account/session/response table.
local Redact = require("lib.redact")
local JSON = require("JSON")
local Diagnostics = {}
local enums = {
  role = { account = true, lock = true },
  bolt = { locked = true, unlocked = true, unknown = true, jammed = true },
  update_channel = { Stable = true, Prerelease = true },
  automatic_updates = { On = true, Off = true },
  log_mode = { Off = true, Print = true, Log = true, ["Print and Log"] = true },
  outcome = {
    none = true,
    queued = true,
    pending = true,
    confirmed = true,
    unconfirmed = true,
    rejected = true,
    fault = true,
    expired = true,
    cancelled = true,
    authentication_failed = true,
  },
}
local numbers = {
  lock_count = true,
  active_commands = true,
  queued_commands = true,
  polling_interval = true,
  srp_public_ms = true,
  srp_proof_ms = true,
  battery_percent = true,
  log_level = true,
}
local booleans = { signed_in = true, polling_fresh = true, online = true, low_battery = true, selected = true }

function Diagnostics.render(data)
  local safe = {}
  for key, values in pairs(enums) do
    safe[key] = values[data[key]] and data[key] or "unknown"
  end
  for key in pairs(numbers) do
    local value = tonumber(data[key])
    if value and value == value and value >= 0 and value < math.huge then
      safe[key] = value
    end
  end
  for key in pairs(booleans) do
    if type(data[key]) == "boolean" then
      safe[key] = data[key]
    end
  end
  if type(data.version) == "string" and data.version:match("^%d+$") then
    safe.version = data.version
  end
  if type(data.os_version) == "string" then
    safe.os_version = data.os_version:match("%d+%.%d+%.%d+")
  end
  return "Schlage local diagnostics (no credentials or device identifiers):\n" .. JSON:encode(Redact.value(safe))
end

return Diagnostics
