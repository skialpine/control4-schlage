-- Once per controller-local date, from fresh public telemetry only. Delivery
-- has independent Composer-event and automatic-push daily allowances.
local Alert = {}
Alert.__index = Alert
local key = "SchlageBatteryAlerts"

local function finite(n)
  return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function day(value)
  return type(value) == "string" and value:match("^%d%d%d%d%-%d%d%-%d%d$") and value or nil
end

function Alert.new(options)
  local records = options.persist:get(key, {}, true)
  if type(records) ~= "table" then
    records = {}
  end
  return setmetatable({
    persist = options.persist,
    now = options.now or os.time,
    date = options.date or os.date,
    fire = options.fire,
    message = options.message,
    status = options.status,
    last = options.last,
    push = options.push,
    push_ready = options.push_ready or function()
      return false
    end,
    name = options.name or function(_, fallback)
      return fallback
    end,
    records = records,
  }, Alert)
end

function Alert:configure(settings)
  self.enabled = settings.enabled == true
  self.push_enabled = settings.push_enabled == true
  self.at = settings.at == nil and "09:00" or settings.at
  self.threshold = settings.threshold == nil and 20 or tonumber(settings.threshold)
  local hour, minute
  if type(self.at) == "string" then
    hour, minute = self.at:match("^(%d%d):(%d%d)$")
  end
  self.minute = hour and tonumber(hour) < 24 and tonumber(minute) < 60 and tonumber(hour) * 60 + tonumber(minute) or nil
  self.valid = self.minute ~= nil and finite(self.threshold) and self.threshold >= 0 and self.threshold <= 100
end

function Alert:update(state, identity)
  self.state, self.identity = state or {}, identity or {}
  return self:check()
end

function Alert:check(test)
  if self.stopped then
    return false
  end
  local s, identity = self.state or {}, self.identity or {}
  local now = self.now()
  local id = type(identity.scope) == "string"
      and type(identity.id) == "string"
      and identity.scope ~= ""
      and identity.id ~= ""
      and (#identity.scope .. ":" .. identity.scope .. identity.id)
    or nil
  local record = id and self.records[id] or nil
  record = type(record) == "table" and record or {}
  local last_epoch = finite(record.at) and record.at >= 1577836800 and record.at <= 4102444800 and record.at or nil
  self.last(last_epoch and self.date("%Y-%m-%d %H:%M:%S %Z", last_epoch) or "Never", last_epoch)
  local event_due, push_due = true, test and self.push_enabled
  local today
  if not test then
    if not self.enabled then
      self.status("Disabled")
      return false
    end
    if not self.valid then
      self.status("Invalid alert time or threshold; use HH:MM and 0-100%")
      return false
    end
    if not finite(now) or now < 1577836800 then
      self.status("Waiting for controller clock")
      return false
    end
    if
      not id
      or s.online ~= true
      or s.supported ~= true
      or not finite(s.updated_at)
      or now < s.updated_at
      or now - s.updated_at > 120
    then
      self.status("Waiting for fresh online battery data")
      return false
    end
    local percent = finite(s.battery) and s.battery >= 0 and s.battery <= 100 and s.battery or nil
    if s.low_battery ~= true and not (percent and percent <= self.threshold) then
      self.status("Battery is not low or has no qualifying reading")
      return false
    end
    local clock = self.date("*t", now)
    today = self.date("%Y-%m-%d", now)
    event_due = not day(record.day) or record.day < today
    push_due = self.push_enabled and (not day(record.push_day) or record.push_day < today)
    if not event_due and not push_due then
      self.status("Daily alert already emitted today")
      return false
    end
    if clock.hour * 60 + clock.min < self.minute then
      self.status("Low battery; waiting until " .. self.at .. " local time")
      return false
    end
    -- Durable before the event: reentrant programming, reloads and selecting a
    -- different lock cannot reset the same physical lock's daily allowance.
    push_due = push_due and self.push_ready()
    if not event_due and not push_due then
      self.status("Daily event already emitted; waiting for push service")
      return false
    end
    self.records[id] = {
      day = event_due and today or record.day,
      push_day = push_due and today or record.push_day,
      at = now,
    }
    self.persist:set(key, self.records, true)
    self.last(self.date("%Y-%m-%d %H:%M:%S %Z", now), now)
  end
  local name = self.name(identity, s.name)
  name = type(name) == "string" and name:gsub("[%z\1-\31\127]", " "):sub(1, 120) or ""
  if name == "" then
    name = "Schlage lock"
  end
  local percent = finite(s.battery) and s.battery >= 0 and s.battery <= 100 and string.format(" (%.0f%%)", s.battery)
    or ""
  local message = (test and "TEST: " or "") .. "Low battery: " .. name .. percent .. ". Replace the lock batteries."
  self.message(message)
  if event_due then
    self.fire()
  end
  local result = test and "Test alert event emitted" or "Daily alert event emitted"
  if push_due and self.push_ready() then
    local ok, accepted = pcall(self.push, identity, message, test == true)
    if ok and accepted == "queued" then
      result = "Automatic push queued"
    else
      result = (ok and accepted) and "Push submitted; phone delivery is not confirmed" or "Push submission failed"
    end
  elseif self.push_enabled then
    result = result .. "; waiting for push service"
  else
    result = result .. "; automatic push is Off"
  end
  self.status(result)
  return true
end

function Alert:stop()
  self.stopped = true
end

return Alert
