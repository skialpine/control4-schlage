-- Project lifecycle around the template's release updater and shared settings.
local GitHub = require("lib.github-updater")
local Shared = require("lib.update-settings")
local filenames = require("lib.driver-filenames")
local Updates = {}
Updates.__index = Updates
Updates.REPOSITORY = "skialpine/control4-schlage"
local defaults = { ["Automatic Updates"] = "On", ["Update Channel"] = "Stable" }
local allowed = {
  ["Automatic Updates"] = { On = true, Off = true },
  ["Update Channel"] = { Stable = true, Prerelease = true },
}

function Updates.coordinator()
  local first
  for id in pairs(C4:GetDevicesByC4iName("schlage_account.c4z") or {}) do
    id = tonumber(id)
    if id and (not first or id < first) then
      first = id
    end
  end
  return first
end

function Updates.settings(options)
  options = options or {}
  local self = { values = {}, filenames = options.filenames or filenames, shared = options.shared or Shared }
  for name, default in pairs(defaults) do
    local value = Properties[name]
    self.values[name] = allowed[name][value] and value or default
  end
  function self:get(name)
    return self.values[name]
  end
  function self:changed(name)
    if not allowed[name] then
      return false
    end
    local value = Properties[name]
    if allowed[name][value] and self.values[name] ~= value then
      self.values[name] = value -- set before sending to avoid callback echoes
      self.shared:share(name, value, self.filenames)
    end
    return true
  end
  function self:peer(id)
    for _, filename in ipairs(self.filenames) do
      local peers = C4:GetDevicesByC4iName(filename) or {}
      if peers[id] ~= nil or peers[tostring(id)] ~= nil then
        return true
      end
    end
    return false
  end
  function self:execute(command, params)
    params = params or {}
    if command == "SET_UPDATE_SETTING" then
      if allowed[params.Name] and allowed[params.Name][params.Value] then
        self.values[params.Name] = params.Value
        self.shared:take(params)
      end
      return true
    elseif command == "SCHLAGE_GET_UPDATE_SETTINGS" then
      local source = tonumber(params.SOURCE)
      if source and self:peer(source) then
        for name, value in pairs(self.values) do
          C4:SendToDevice(source, "SET_UPDATE_SETTING", { Name = name, Value = value }, true, false)
        end
      end
      return true
    end
    return false
  end
  function self:sync()
    local leader = Updates.coordinator()
    if leader == C4:GetDeviceID() then
      for name, value in pairs(self.values) do
        self.shared:share(name, value, self.filenames)
      end
    elseif leader then
      C4:SendToDevice(leader, "SCHLAGE_GET_UPDATE_SETTINGS", { SOURCE = tostring(C4:GetDeviceID()) }, true, false)
    end
  end
  return self
end

function Updates.new(options)
  return setmetatable({
    github = options.github or GitHub,
    filenames = options.filenames or filenames,
    schedule = options.schedule,
    setting = options.setting,
    busy = options.busy or function()
      return false
    end,
    coordinator = options.coordinator or Updates.coordinator,
    id = options.id or C4:GetDeviceID(),
    send = options.send or function(id, command)
      C4:SendToDevice(id, command, {}, true, false)
    end,
    status = options.status or function() end,
    checked = options.checked or function() end,
    announce = options.announce or function() end,
    generation = 0,
    running = false,
  }, Updates)
end

function Updates:later(seconds, manual)
  if self.timer then
    self.timer.cancel()
  end
  local generation = self.generation
  self.timer = self.schedule(seconds, function()
    self.timer = nil
    if self.running and self.generation == generation then
      self:check(manual)
    end
  end)
end

function Updates:configure()
  if not self.running or self.active then
    return
  end
  if self.timer then
    self.timer.cancel()
    self.timer = nil
  end
  if self.setting("Automatic Updates") == "On" then
    self.status("Automatic checks enabled")
    self:later(60, false)
  else
    self.status("Automatic updates disabled")
  end
end

function Updates:start()
  self.running = true
  self:configure()
end

function Updates:stop()
  self.running = false
  self.active = false
  self.generation = self.generation + 1
  if self.timer then
    self.timer.cancel()
    self.timer = nil
  end
end

function Updates:check(manual)
  if not self.running then
    return
  end
  if self.active then
    if manual then
      self.announce("Update check already in progress")
    end
    return
  end
  if not manual and self.setting("Automatic Updates") ~= "On" then
    return
  end
  if self.timer then
    self.timer.cancel()
    self.timer = nil
  end
  local leader = self.coordinator()
  if leader and leader ~= self.id then
    self.status("Managed by account " .. tostring(leader))
    if manual then
      self.send(leader, "Check_for_Updates")
      self.announce("Update check requested from the coordinating account")
    end
    if self.setting("Automatic Updates") == "On" then
      self:later(21600, false)
    end
    return
  end
  if self.busy() then
    self.status("Waiting for lock commands")
    if manual then
      self.announce("Update check waiting for lock commands")
    end
    self:later(5, manual)
    return
  end
  self.active = true
  local generation = self.generation
  self.status("Checking GitHub releases")
  self.checked(os.time())
  if manual then
    self.announce("Checking GitHub releases")
  end
  local function finish(ok, result)
    if not self.running or generation ~= self.generation then
      return
    end
    self.active = false
    local message
    if ok and type(result) == "table" then
      message = #result == 0 and "Up to date" or "Installing updated drivers"
    elseif type(result) == "string" and result:find("does not have any valid releases", 1, true) then
      message = "No release available in this channel"
    else
      -- Do not expose response tables or raw error strings to Properties/logs.
      message = "Update check failed; check release availability and internet access"
    end
    self.status(message)
    if manual then
      self.announce(message)
    end
    if self.setting("Automatic Updates") == "On" then
      self:later(21600, false)
    end
  end
  local ok = pcall(function()
    self.github
      :updateAll(Updates.REPOSITORY, self.filenames, self.setting("Update Channel") == "Prerelease", false)
      :next(function(result)
        finish(true, result)
      end, function(err)
        finish(false, err)
      end)
  end)
  if not ok then
    finish(false)
  end
end

return Updates
