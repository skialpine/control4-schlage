-- Fail-closed diagnostic summaries: raw cloud documents and serialized bodies
-- are opaque. Only explicitly known status words and numeric metrics may pass.
local M = {}
local categories = {}
for word in
  (
    "signed_in signed_out signing_in renewing retry_wait sign_in_required credentials_required "
    .. "crypto_unavailable crypto_budget_exceeded invalid_challenge unsupported_challenge malformed_response "
    .. "transport_error transient_error unauthorized rate_limited http_error cancelled backoff storage_error "
    .. "discovery_ok initializing unknown_error"
  ):gmatch("%S+")
do
  categories[word] = true
end

function M.category(value)
  return categories[value] and value or "unknown_error"
end

function M.value(value)
  if type(value) ~= "table" then
    return "[REDACTED]"
  end
  local out = {}
  for key, item in pairs(value) do
    if key == "category" then
      out[key] = M.category(item)
    elseif
      (key == "code" or key == "elapsed_ms" or key == "count")
      and type(item) == "number"
      and item == item
      and math.abs(item) < math.huge
    then
      out[key] = item
    else
      out.redacted_fields = (out.redacted_fields or 0) + 1
    end
  end
  return out
end

return M
