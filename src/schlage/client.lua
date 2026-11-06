-- Authenticated discovery; retained objects are normalized public fields only.
local Device = require("schlage.device")
local Client = {}
Client.__index = Client

function Client.new(account, transport, now)
  return setmetatable({
    account = account,
    transport = transport,
    jobs = {},
    devices = {},
    sequence = 0,
    revisions = {},
    accepted = {},
    observed_at = {},
    observed_epoch = {},
    read_sequence = 0,
    now = now or os.time,
  }, Client)
end

function Client:mark_write(id)
  self.revisions[id] = (self.revisions[id] or 0) + 1
end

function Client:stamp()
  self.read_sequence = self.read_sequence + 1
  local revisions = {}
  for id, revision in pairs(self.revisions) do
    revisions[id] = revision
  end
  return { sequence = self.read_sequence, revisions = revisions }
end

function Client:current(id, stamp)
  return (self.revisions[id] or 0) == (stamp.revisions[id] or 0) and stamp.sequence >= (self.accepted[id] or 0)
end

function Client:cancel()
  local jobs = self.jobs
  self.jobs = {}
  self.devices = {}
  self.observed_at, self.revisions, self.accepted = {}, {}, {}
  self.observed_epoch = {}
  self.sequence = self.sequence + 1
  for job in pairs(jobs) do
    job.done = true
    if job.handle then
      job.handle.cancel()
    end
    job.callback(nil, { category = "cancelled" })
  end
end

function Client:discover(callback)
  local generation = self.account.generation
  self.sequence = self.sequence + 1
  local sequence = self.sequence
  local job = { callback = callback }
  self.jobs[job] = true
  local function finish(value, err)
    if job.done then
      return
    end
    job.done = true
    self.jobs[job] = nil
    if self.account.destroyed or generation ~= self.account.generation or sequence ~= self.sequence then
      callback(nil, { category = "cancelled" })
      return
    end
    callback(value, err)
  end
  local refreshed = false
  local authenticate
  authenticate = function(force)
    self.account:ensure(function(session, err)
      if job.done then
        return
      end
      if err then
        finish(nil, err)
        return
      end
      if generation ~= self.account.generation or sequence ~= self.sequence then
        finish(nil, { category = "cancelled" })
        return
      end
      if self.can_request then
        local allowed, delay = self.can_request()
        if not allowed then
          finish(nil, { category = "rate_limited", retry_after = delay })
          return
        end
      end
      local stamp = self:stamp()
      job.handle = self.transport:devices(session.access_token, function(data, failure)
        if job.done then
          return
        end
        if failure then
          if failure.category == "unauthorized" and not refreshed then
            refreshed = true
            authenticate(true)
            return
          end
          finish(nil, failure)
          return
        end
        local devices, failure, by_id = Device.list(data)
        if failure then
          finish(nil, failure)
          return
        end
        if not self.account.destroyed and generation == self.account.generation and sequence == self.sequence then
          local effective = {}
          for id, device in pairs(by_id) do
            if self:current(id, stamp) then
              effective[id], self.accepted[id], self.observed_at[id] = device, stamp.sequence, self.now()
              self.observed_epoch[id] = os.time()
            elseif self.devices[id] then
              effective[id] = self.devices[id]
            end
          end
          for id, device in pairs(self.devices) do
            if not by_id[id] then
              if self:current(id, stamp) then
                self.accepted[id], self.observed_at[id] = stamp.sequence, nil
                self.observed_epoch[id] = nil
              else
                effective[id] = device
              end
            end
          end
          local result, emitted = {}, {}
          for _, device in ipairs(devices) do
            if effective[device.id] then
              result[#result + 1], emitted[device.id] = effective[device.id], true
            end
          end
          for id, device in pairs(effective) do
            if not emitted[id] then
              result[#result + 1] = device
            end
          end
          self.devices, devices = effective, result
        end
        finish(devices)
      end)
    end, force)
  end
  authenticate(false)
end

function Client:read(id, callback)
  local generation, job = self.account.generation, { callback = callback }
  self.jobs[job] = true
  local function finish(value, err)
    if job.done then
      return
    end
    job.done, self.jobs[job] = true, nil
    if self.account.destroyed or generation ~= self.account.generation then
      callback(nil, { category = "cancelled" })
    else
      callback(value, err)
    end
  end
  self.account:ensure(function(session, err)
    if job.done then
      return
    end
    if err then
      finish(nil, err)
      return
    end
    if generation ~= self.account.generation then
      finish(nil, { category = "cancelled" })
      return
    end
    if self.can_request then
      local allowed, delay = self.can_request()
      if not allowed then
        finish(nil, { category = "rate_limited", retry_after = delay })
        return
      end
    end
    local stamp = self:stamp()
    job.handle = self.transport:device(session.access_token, id, function(raw, failure)
      if job.done then
        return
      end
      if failure then
        finish(nil, failure)
        return
      end
      local device, malformed = Device.normalize(raw)
      if not device or device.id ~= id then
        finish(nil, malformed or { category = "malformed_response" })
        return
      end
      if generation ~= self.account.generation or not self:current(id, stamp) then
        finish(nil, { category = "cancelled" })
        return
      end
      self.devices[id], self.accepted[id], self.observed_at[id] = device, stamp.sequence, self.now()
      self.observed_epoch[id] = os.time()
      if self.on_device then
        self.on_device(device)
      end
      finish(device)
    end)
  end)
  return {
    cancel = function()
      if job.handle then
        job.handle.cancel()
      end
      finish(nil, { category = "cancelled" })
    end,
  }
end

return Client
