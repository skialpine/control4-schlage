-- Driver-owned native notification templates. Never reuse another driver's
-- message. Native writes have no acknowledgement: read them back before SEND.
require("lib.utils")
local Push = {}
Push.__index = Push

local function templates(xml)
  if type(xml) ~= "string" or #xml > 1024 * 1024 then
    return nil
  end
  local ok, parsed = pcall(ParseXml, xml)
  if not ok or parsed.templates == nil then
    return nil
  end
  local rows = type(parsed.templates) == "table" and parsed.templates.template or nil
  if rows == nil then
    return {}
  end
  if type(rows) ~= "table" then
    return nil
  end
  if rows.templateid then
    rows = { rows }
  end
  local result = {}
  for _, row in ipairs(rows) do
    local id = tonumber(row.templateid)
    if id and id > 0 and id % 1 == 0 and type(row.name) == "string" then
      result[#result + 1] = { id = id, name = row.name, message = row.message or "", subject = row.subject or "" }
    end
  end
  return result
end

local function template_xml(id, job)
  return "<template><templateid>"
    .. id
    .. "</templateid><name>"
    .. XMLEncode(job.name)
    .. "</name><category>2</category><severity>3</severity><subject>"
    .. XMLEncode(job.subject)
    .. "</subject><message>"
    .. XMLEncode(job.message)
    .. "</message><timestamp>1</timestamp><attachments/></template>"
end

function Push.new(options)
  return setmetatable({
    owner = options.owner,
    token = options.token,
    agent = options.agent or function()
      return GetAgentId("control4_agent_notification.c4i")
    end,
    read = options.read or function(id)
      return C4:SendUIRequest(id, "GET_TEMPLATE_LIST", {})
    end,
    send = options.send or function(id, command, params)
      C4:SendToDevice(id, command, params, true, false)
    end,
    now = options.now,
    schedule = options.schedule,
    valid = options.valid,
    status = options.status,
    generation = 0,
    jobs = {},
    enabled = false,
  }, Push)
end

function Push:cancel()
  self.generation = self.generation + 1
  if self.timer then
    self.timer.cancel()
    self.timer = nil
  end
  self.jobs, self.active = {}, nil
end

function Push:configure(enabled)
  if self.enabled ~= (enabled == true) then
    self:cancel()
  end
  self.enabled = enabled == true
end

function Push:ready()
  local ready = self.enabled and self:_agent() ~= nil
  if self.enabled and not ready then
    self.status("Control4 Push Notification agent is unavailable")
  end
  return ready
end

function Push:_agent()
  local ok, value = pcall(self.agent)
  value = ok and tonumber(value) or nil
  return value and value > 0 and value < math.huge and value % 1 == 0 and value or nil
end

function Push:submit(identity, message, test)
  if not self:ready() then
    return false
  end
  local ok, token = pcall(self.token, identity)
  if not ok then
    return false
  end
  if type(token) ~= "string" or not token:match("^[a-f0-9]+$") then
    return false
  end
  local job = {
    identity = { scope = identity.scope, id = identity.id },
    message = message,
    name = "Schlage Low Battery [" .. tostring(self.owner) .. ":" .. token .. "]",
    subject = test and "TEST: Schlage lock battery alert" or "Schlage lock battery low",
    test = test,
    expires = self.now() + 30,
  }
  self.jobs[#self.jobs + 1] = job
  self:_next()
  return "queued"
end

function Push:_current(job)
  local ok, valid = pcall(self.valid, job.identity, job.test)
  return self.enabled
    and self.active == job
    and self.now() <= job.expires
    and ok
    and valid
    and self:_agent() == job.agent
end

function Push:_finish(job, status)
  if self.active ~= job then
    return
  end
  self.active = nil
  if self.timer then
    self.timer.cancel()
    self.timer = nil
  end
  self.status(status)
  self:_next()
end

function Push:_read(job)
  local ok, xml = pcall(self.read, job.agent)
  local list = ok and templates(xml) or nil
  if not list then
    return nil, "Cannot read Control4 push notifications"
  end
  local found
  for _, row in ipairs(list) do
    if row.name == job.name then
      if found then
        return nil, "Duplicate Schlage notification entries; push not submitted"
      end
      found = row
    end
  end
  return found or false
end

function Push:_verify(job, attempt)
  if not self:_current(job) then
    self:_finish(job, "Push cancelled: settings or battery data changed")
    return
  end
  local row, err = self:_read(job)
  if err then
    self:_finish(job, err)
    return
  end
  if row and row.message == job.message and row.subject == job.subject then
    local ok = pcall(self.send, job.agent, "SEND_NOTIFICATION", { TEMPLATE_ID = tostring(row.id) })
    self:_finish(job, ok and "Push submitted to Control4; phone delivery is not confirmed" or "Push submission failed")
    return
  end
  if attempt >= 10 then
    self:_finish(job, "Schlage notification setup was not confirmed; push not submitted")
    return
  end
  local generation = self.generation
  self.timer = self.schedule(0.2, function()
    self.timer = nil
    if generation == self.generation then
      self:_verify(job, attempt + 1)
    end
  end)
end

function Push:_next()
  if self.active or not self.enabled then
    return
  end
  local job = table.remove(self.jobs, 1)
  if not job then
    return
  end
  self.active = job
  job.agent = self:_agent()
  if not job.agent or not self:_current(job) then
    self:_finish(job, "Push cancelled: settings, agent, or battery data unavailable")
    return
  end
  local row, err = self:_read(job)
  if err then
    self:_finish(job, err)
    return
  end
  if not row or row.message ~= job.message or row.subject ~= job.subject then
    local command = row and "MODIFY_TEMPLATE" or "ADD_TEMPLATE"
    local ok = pcall(self.send, job.agent, command, { TEMPLATE_XML = template_xml(row and row.id or 0, job) })
    if not ok then
      self:_finish(job, "Cannot configure Schlage notification; push not submitted")
      return
    end
  end
  self:_verify(job, 0)
end

function Push:stop()
  self:configure(false)
  self:cancel()
end

return Push
