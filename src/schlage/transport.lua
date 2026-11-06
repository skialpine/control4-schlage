-- Schlage protocol boundary over the template's shared asynchronous URL library.
-- Raw requests/responses are never handed to the logger or to a companion.
require("drivers-common-public.global.url")
-- Shared URL parsing uses this strict codec, retaining [] versus {}.
JSON = require("JSON"):new({ strictTypes = true })
local log = require("lib.logging")
local retry_after = require("schlage.retry_after")
local Transport = {}
Transport.__index = Transport

function Transport.quiet()
  DEBUGPRINT, DEBUG_URL, DEBUG_RFN, DEBUG_WEBSOCKET, DEBUG_TIMER = false, false, false, false, false
end

function Transport.new(config)
  Transport.quiet()
  return setmetatable({ config = config }, Transport)
end

local permanent = {
  NotAuthorizedException = true,
  InvalidPasswordException = true,
  PasswordResetRequiredException = true,
  UserNotFoundException = true,
  UserNotConfirmedException = true,
}

function Transport:request(method, url, body, headers, callback)
  Transport.quiet()
  local finished, transfer = false, nil
  local function done(data, err)
    if finished then
      return
    end
    finished = true
    local ok = pcall(callback, data, err)
    if not ok then
      log:error("Schlage response handling failed")
    end
  end
  local ok = pcall(function()
    -- Encode here: shared urlDo otherwise overwrites Cognito's content type.
    local encoded = body and JSON:encode(body) or nil
    transfer = urlDo(method, url, encoded, headers, function(network_error, code, response_headers, data)
      Transport.quiet()
      if finished then
        return
      end
      code = tonumber(code) or 0
      local parsed = data
      if type(data) == "string" then
        local decoded, value = pcall(JSON.decode, JSON, data)
        parsed = decoded and value or nil
      end
      local kind = type(parsed) == "table" and parsed.__type
      kind = type(kind) == "string" and kind:match("([^#]+)$") or nil
      if network_error or code == 0 then
        done(nil, { category = "transport_error", code = code })
      elseif code < 200 or code >= 300 then
        local category = "http_error"
        if permanent[kind] then
          category = "sign_in_required"
        elseif code == 401 then
          category = "unauthorized"
        elseif code == 429 or kind == "TooManyRequestsException" then
          category = "rate_limited"
        elseif code >= 500 then
          category = "transient_error"
        end
        local retry
        for name, value in pairs(response_headers or {}) do
          if type(name) == "string" and name:lower() == "retry-after" then
            retry = retry_after(value, os.time())
          end
        end
        done(nil, { category = category, code = code, retry_after = retry })
      elseif method == "PUT" and (data == nil or data == "") then
        done({})
      elseif type(parsed) ~= "table" then
        done(nil, { category = "malformed_response", code = code })
      else
        done(parsed)
      end
    end, nil, { timeout = self.config.timeout, connect_timeout = 5, ssl_verify_host = true, cookies_enable = false })
  end)
  if not ok then
    done(nil, { category = "transport_error" })
  end
  return {
    cancel = function()
      finished = true
      if transfer and type(transfer.Cancel) == "function" then
        pcall(transfer.Cancel, transfer)
      end
    end,
  }
end

function Transport:cognito(action, body, callback)
  return self:request("POST", self.config.cognito_url, body, {
    ["Content-Type"] = "application/x-amz-json-1.1",
    ["X-Amz-Target"] = "AWSCognitoIdentityProviderService." .. action,
  }, callback)
end

function Transport:devices(token, callback)
  return self:request("GET", self.config.api_url .. "/devices?archetype=lock", nil, {
    Authorization = "Bearer " .. token,
    ["X-Api-Key"] = self.config.api_key,
  }, callback)
end

local function segment(id)
  assert(type(id) == "string" and id ~= "", "Device ID required")
  return (id:gsub("[^%w%-%._~]", function(c)
    return string.format("%%%02X", c:byte())
  end))
end

function Transport:device(token, id, callback)
  return self:request("GET", self.config.api_url .. "/devices/" .. segment(id), nil, {
    Authorization = "Bearer " .. token,
    ["X-Api-Key"] = self.config.api_key,
  }, callback)
end

function Transport:write(token, id, locked, callback)
  assert(type(locked) == "boolean", "Explicit lock intent required")
  return self:request(
    "PUT",
    self.config.api_url .. "/devices/" .. segment(id),
    { attributes = { lockState = locked and 1 or 0 } },
    {
      Authorization = "Bearer " .. token,
      ["X-Api-Key"] = self.config.api_key,
      ["Content-Type"] = "application/json",
    },
    callback
  )
end

return Transport
