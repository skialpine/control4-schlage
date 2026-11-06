-- One scheduled account listing in flight; reads and writes share the cooldown.
local Poller = {}
Poller.__index = Poller

function Poller.new(options)
  return setmetatable({
    client = options.client,
    schedule = options.schedule,
    now = options.now or os.time,
    jitter = options.jitter or math.random,
    on_result = options.on_result or function() end,
    on_stale = options.on_stale or function() end,
    interval = 30,
    generation = 0,
    attempts = 0,
    running = false,
    waiters = {},
    blocked_until = 0,
  }, Poller)
end

function Poller:set_interval(seconds)
  seconds = tonumber(seconds)
  self.interval = seconds and seconds == seconds and math.min(3600, math.max(15, math.floor(seconds))) or 30
  if self.running and not self.active then
    self:_next(self.interval)
  end
end

function Poller:_next(seconds)
  if self.timer then
    self.timer.cancel()
  end
  local generation = self.generation
  -- Native timer durations are finite; a long server delay is rechecked on wake.
  self.timer = self.schedule(math.min(86400, math.max(1, seconds)), function()
    self.timer = nil
    if generation == self.generation and self.running then
      self:refresh()
    end
  end)
end

function Poller:cooldown(err)
  if err and err.category == "rate_limited" then
    local delay = err.retry_after
    if type(delay) ~= "number" or delay < 0 or delay ~= delay or delay == math.huge then
      delay = 60
    end
    self.blocked_until = math.max(self.blocked_until, self.now() + delay)
  end
end

function Poller:can_request()
  return self.running and self.now() >= self.blocked_until
end

function Poller:fresh()
  return self.running
    and self.last_success ~= nil
    and self.now() >= self.last_success
    and self.now() - self.last_success < 120
end

function Poller:start()
  self.running = true
  self:refresh()
end

function Poller:stop()
  self.generation = self.generation + 1
  self.running, self.active, self.last_success, self.attempts, self.blocked_until = false, false, nil, 0, 0
  if self.timer then
    self.timer.cancel()
    self.timer = nil
  end
  if self.stale_timer then
    self.stale_timer.cancel()
    self.stale_timer = nil
  end
  self.client:cancel()
  local waiters = self.waiters
  self.waiters = {}
  for _, callback in ipairs(waiters) do
    callback(nil, { category = "cancelled" })
  end
end

function Poller:refresh(callback)
  if not self.running then
    if callback then
      callback(nil, { category = "sign_in_required" })
    end
    return
  end
  if not self:can_request() then
    self:_next(self.blocked_until - self.now())
    if callback then
      callback(nil, { category = "rate_limited", retry_after = self.blocked_until - self.now() })
    end
    return
  end
  if callback then
    self.waiters[#self.waiters + 1] = callback
  end
  if self.active then
    return
  end
  if self.timer then
    self.timer.cancel()
    self.timer = nil
  end
  self.active = true
  local generation = self.generation
  self.client:discover(function(devices, err)
    if generation ~= self.generation or not self.running then
      return
    end
    self.active = false
    if devices then
      self.last_success, self.attempts = self.now(), 0
      if self.stale_timer then
        self.stale_timer.cancel()
      end
      local observed = self.last_success
      self.stale_timer = self.schedule(120, function()
        self.stale_timer = nil
        if generation == self.generation and self.last_success == observed and not self:fresh() then
          self.on_stale()
        end
      end)
      self:_next(self.interval)
    else
      self.attempts = self.attempts + 1
      self:cooldown(err)
      local maximum = math.min(300, 5 * 2 ^ math.min(6, self.attempts))
      local delay = self.jitter(5, maximum)
      self:_next(math.max(delay, self.blocked_until - self.now()))
    end
    local waiters = self.waiters
    self.waiters = {}
    self.on_result(devices, err)
    for _, waiter in ipairs(waiters) do
      waiter(devices, err)
    end
  end)
end

return Poller
