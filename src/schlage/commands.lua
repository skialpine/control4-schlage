-- Volatile, per-lock command scheduling. Mutations are never automatically replayed.
local Commands = {}
Commands.__index = Commands
local read_offsets = { 1, 3, 5, 7, 11, 15, 29 }
local redact = require("schlage.redact")
local public_trace_details = {
  [""] = true,
  locked = true,
  unlocked = true,
  unknown = true,
  jammed = true,
  confirmed = true,
  unconfirmed = true,
  rejected = true,
  fault = true,
  cancelled = true,
  expired = true,
  authentication_failed = true,
}

function Commands.new(options)
  return setmetatable({
    account = options.account,
    client = options.client,
    transport = options.transport,
    registry = options.registry,
    poller = options.poller,
    schedule = options.schedule,
    now = options.now or os.time,
    on_device = options.on_device or function() end,
    on_outcome = options.on_outcome or function() end,
    on_trace = options.on_trace or function() end,
    slots = {},
    generation = 0,
    sequence = 0,
  }, Commands)
end

function Commands:trace(command, phase, detail)
  self.on_trace(
    command.sequence,
    command.locked and "lock" or "unlock",
    phase,
    math.floor(math.max(0, self.now() - command.requested_at) * 1000),
    public_trace_details[detail or ""] and (detail or "") or redact.category(detail)
  )
end

function Commands:valid(id)
  local device = self.registry.devices[id]
  if not device then
    return nil, "unknown_device"
  end
  device = (self.client.devices and self.client.devices[id]) or device
  if not device.supported then
    return nil, "unsupported_device"
  end
  local observed = self.client.observed_at[id]
  if
    not device.connected
    or not self.poller:fresh()
    or not observed
    or self.now() < observed
    or self.now() - observed >= 120
  then
    return nil, "offline"
  end
  return device
end

function Commands:report(slot, command, outcome)
  if command.sequence == slot.latest then
    self.on_outcome(command.id, outcome, command.locked and "lock" or "unlock")
  end
end

function Commands:clear_queue(slot, outcome)
  local command = slot.queue
  slot.queue = nil
  if slot.expiry then
    slot.expiry.cancel()
    slot.expiry = nil
  end
  if slot.wake then
    slot.wake.cancel()
    slot.wake = nil
  end
  if command and outcome then
    self:trace(command, "finished", outcome)
    self:report(slot, command, outcome)
  end
end

function Commands:finish(slot, active, outcome)
  if slot.active ~= active then
    return
  end
  slot.active = nil
  self:trace(active, "finished", outcome)
  if active.deadline_timer then
    active.deadline_timer.cancel()
  end
  if active.read_timer then
    active.read_timer.cancel()
  end
  if active.read_handle then
    active.read_handle.cancel()
  end
  if active.write_handle then
    active.write_handle.cancel()
  end
  self:report(slot, active, outcome)
  self:pump(slot)
end

function Commands:cancel_slot(slot)
  self:clear_queue(slot, "cancelled")
  if slot.active then
    self:finish(slot, slot.active, "cancelled")
  end
end

function Commands:cancel()
  self.generation = self.generation + 1
  for _, slot in pairs(self.slots) do
    self:cancel_slot(slot)
  end
  self.slots = {}
end

function Commands:cancel_device(id)
  if id and self.slots[id] then
    self:cancel_slot(self.slots[id])
  end
end

function Commands:sync()
  for id, slot in pairs(self.slots) do
    if not self:valid(id) then
      self:cancel_slot(slot)
    else
      local command = slot.active
      -- Discovery may finish before the next individual read. Only use a
      -- client-accepted observation issued after this write, never a retained
      -- pre-write cache entry. Wait for the write callback before releasing
      -- serialization, including when the observed target already matches.
      if
        command
        and command.acknowledged ~= nil
        and self.now() < command.deadline
        and self.client.revisions[id] == command.revision
        and (self.client.accepted[id] or 0) > command.read_sequence
      then
        local device = self.client.devices[id]
        self:trace(command, "poll_readback", device.bolt)
        self:reconcile(slot, command, device)
      end
    end
  end
end

function Commands:reconcile(slot, command, device)
  if not device.supported or not device.connected then
    self:finish(slot, command, "unconfirmed")
  elseif device.bolt == "jammed" then
    self:finish(slot, command, "fault")
  elseif device.bolt == (command.locked and "locked" or "unlocked") then
    self:finish(slot, command, command.rejected and "rejected" or "confirmed")
  end
end

function Commands:request(id, action)
  if type(id) ~= "string" or id == "" then
    return false
  end
  self.sequence = self.sequence + 1
  local slot = self.slots[id] or {}
  self.slots[id], slot.latest = slot, self.sequence
  local device, reason = self:valid(id)
  local locked = action == "LOCK"
  if action == "TOGGLE" then
    if device and (device.bolt == "locked" or device.bolt == "unlocked") then
      -- The generic Door Lock sends TOGGLE on every tap. While its cloud
      -- observation lags, reverse the latest live target rather than resolving
      -- repeated taps to the same mutation. Reported state is never changed.
      local previous = slot.queue and slot.queue.expires > self.now() and slot.queue or nil
      if not previous and slot.active and slot.active.deadline > self.now() and slot.active.acknowledged ~= false then
        previous = slot.active
      end
      if previous then
        locked = not previous.locked
      else
        locked = device.bolt == "unlocked"
      end
    else
      reason = reason or "state_unknown"
    end
  elseif action ~= "LOCK" and action ~= "UNLOCK" then
    reason = "invalid_command"
  end
  local command = {
    id = id,
    locked = locked,
    sequence = self.sequence,
    requested_at = self.now(),
    expires = self.now() + 30,
  }
  self:trace(command, "requested")
  if reason then
    self:clear_queue(slot)
    self:report(slot, command, "rejected: " .. reason)
    return false
  end
  self:clear_queue(slot)
  slot.queue = command
  self:report(slot, command, "queued")
  slot.expiry = self.schedule(30, function()
    if slot.queue == command then
      self:clear_queue(slot, "expired")
    end
  end)
  self:pump(slot)
  return true
end

function Commands:wait_cooldown(slot)
  if slot.wake then
    slot.wake.cancel()
  end
  slot.wake = self.schedule(math.max(1, math.min(30, self.poller.blocked_until - self.now())), function()
    slot.wake = nil
    self:pump(slot)
  end)
end

function Commands:pump(slot)
  if slot.active then
    -- Serialize the cloud mutations, not the full confirmation window. A newer
    -- explicit intent may replace readback after a successful acknowledgement.
    -- Uncertain or rejected writes retain their reconciliation barrier.
    if slot.queue and slot.active.acknowledged then
      self:trace(slot.active, "readback_superseded")
      self:finish(slot, slot.active, "unconfirmed")
    end
    return
  end
  if slot.preparing or not slot.queue then
    return
  end
  local command = slot.queue
  if self.now() >= command.expires then
    self:clear_queue(slot, "expired")
    return
  end
  if not self:valid(command.id) then
    self:clear_queue(slot, "cancelled")
    return
  end
  if not self.poller:can_request() then
    self:wait_cooldown(slot)
    return
  end
  local generation = self.generation
  slot.preparing = true
  self.account:ensure(function(session, err)
    slot.preparing = false
    if generation ~= self.generation or not slot.queue then
      return
    end
    command = slot.queue -- a newer unsent intent may have replaced the original
    if self.now() >= command.expires then
      self:clear_queue(slot, "expired")
      return
    end
    if err then
      self:clear_queue(slot, "authentication_failed")
      return
    end
    if not self:valid(command.id) then
      self:clear_queue(slot, "cancelled")
      return
    end
    if not self.poller:can_request() then
      self:wait_cooldown(slot)
      return
    end
    self:clear_queue(slot)
    slot.active = command
    command.started, command.deadline, command.read_index = self.now(), self.now() + 30, 0
    -- Advance on dispatch, including writes that later time out or are rejected.
    self.client:mark_write(command.id)
    command.revision = self.client.revisions[command.id]
    command.read_sequence = self.client.read_sequence or 0
    self:trace(command, "dispatched")
    self:report(slot, command, "pending")
    command.deadline_timer = self.schedule(30, function()
      self:finish(slot, command, "unconfirmed")
    end)
    command.write_handle = self.transport:write(session.access_token, command.id, command.locked, function(_, failure)
      if generation ~= self.generation or slot.active ~= command then
        return
      end
      self.poller:cooldown(failure)
      command.acknowledged = failure == nil
      self:trace(command, failure and "cloud_failed" or "cloud_accepted", failure and failure.category)
      command.rejected = failure
        and (
          failure.category == "unauthorized"
          or failure.category == "rate_limited"
          or failure.category == "http_error"
        )
      if command.acknowledged and slot.queue then
        self:pump(slot)
        if slot.active ~= command then
          return
        end
      end
      if failure and failure.category == "unauthorized" then
        self.account:ensure(function(_, refresh_error)
          if generation ~= self.generation or slot.active ~= command then
            return
          end
          if refresh_error then
            self:finish(slot, command, "unconfirmed")
          else
            self:readback(slot, command)
          end
        end, true)
      else
        self:readback(slot, command)
      end
    end)
  end)
end

function Commands:readback(slot, command)
  if slot.active ~= command or self.now() >= command.deadline then
    return
  end
  command.read_index = command.read_index + 1
  local offset = read_offsets[command.read_index]
  if not offset then
    return
  end
  local when = math.max(self.now(), command.started + offset, self.poller.blocked_until)
  if when >= command.deadline then
    return
  end
  command.read_timer = self.schedule(math.max(0.001, when - self.now()), function()
    command.read_timer = nil
    if slot.active ~= command or self.now() >= command.deadline then
      return
    end
    if not self.poller:can_request() then
      command.read_index = command.read_index - 1
      self:readback(slot, command)
      return
    end
    command.read_handle = self.client:read(command.id, function(device, err)
      if slot.active ~= command or self.now() >= command.deadline then
        return
      end
      self.poller:cooldown(err)
      self:trace(command, "readback", device and device.bolt or (err and err.category))
      if device then
        self.on_device(device)
        self:reconcile(slot, command, device)
        if slot.active ~= command then
          return
        end
      elseif err and err.category == "unauthorized" then
        -- Safe refresh for subsequent reads; the mutation remains single-shot.
        self.account:ensure(function() end, true)
      end
      while
        read_offsets[command.read_index + 1] and command.started + read_offsets[command.read_index + 1] <= self.now()
      do
        command.read_index = command.read_index + 1
      end
      self:readback(slot, command)
    end)
  end)
end

return Commands
