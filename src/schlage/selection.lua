-- Installer selection belongs to each companion, independent of room placement.
local Selection = {}
Selection.__index = Selection
Selection.NONE_ACCOUNT, Selection.NONE_LOCK = "Select an account", "Select a lock"
local function clean(value)
  return tostring(value or ""):gsub("[%z\1-\31\127,]", " "):sub(1, 100)
end

function Selection.new(options)
  local saved = options.store:get("SchlageSelection", {})
  if type(saved) ~= "table" then
    saved = {}
  end
  local identity = options.identity() or {}
  local bound = options.provider()
  local configured = saved.schema == 1 and type(saved.id) == "string" and type(saved.scope) == "string"
  if configured then
    identity = saved
  end
  local account
  if configured then
    account = tonumber(saved.account)
  elseif bound > 0 then
    account = bound
  end
  return setmetatable({
    store = options.store,
    accounts = options.accounts,
    provider = options.provider,
    nonce = options.nonce,
    send = options.send,
    detach = options.detach,
    on_lists = options.on_lists,
    on_status = options.on_status,
    on_selected = options.on_selected,
    account = account,
    id = type(identity.id) == "string" and identity.id or (type(saved.id) == "string" and saved.id or ""),
    scope = type(identity.scope) == "string" and identity.scope
      or (type(saved.scope) == "string" and saved.scope or ""),
    auto_account = not configured and bound == 0 and not identity.id,
    allow_adopt = not configured and bound > 0,
    account_labels = {},
    lock_labels = {},
    alive = true,
  }, Selection)
end

function Selection:save()
  self.store:set("SchlageSelection", { schema = 1, account = self.account, id = self.id, scope = self.scope })
end

function Selection:refresh()
  local available, count, only = self.accounts(), 0, nil
  self.account_labels = {}
  local labels, selected = { Selection.NONE_ACCOUNT }, Selection.NONE_ACCOUNT
  for key, name in pairs(available) do
    local id = tonumber(key)
    if id then
      local label = tostring(id) .. ": " .. clean(name)
      self.account_labels[label] = id
      labels[#labels + 1], count, only = label, count + 1, id
      if id == self.account then
        selected = label
      end
    end
  end
  if not self.account and self.auto_account and count == 1 then
    self.account = only
  end
  for label, id in pairs(self.account_labels) do
    if id == self.account then
      selected = label
    end
  end
  if self.account and selected == Selection.NONE_ACCOUNT then
    selected = tostring(self.account) .. ": Unavailable account"
    labels[#labels + 1] = selected
  end
  table.sort(labels)
  self.account_items, self.account_label = labels, selected
  self.lock_labels = {}
  self.on_lists(labels, selected, { Selection.NONE_LOCK }, Selection.NONE_LOCK)
  self.request_nonce = self.nonce()
  self.pending = self.id ~= "" and self.provider() == 0
  if selected == Selection.NONE_ACCOUNT or not (available[self.account] or available[tostring(self.account)]) then
    self.on_status(self.account and "Selected account unavailable" or "Select an account")
    return
  end
  self.on_status("Waiting for discovered locks")
  self.send(self.account, "SCHLAGE_CATALOG_REQUEST", { NONCE = self.request_nonce })
end

function Selection:choose_account(label)
  local account = self.account_labels[label]
  if label ~= Selection.NONE_ACCOUNT and not account then
    return
  end
  if account == self.account then
    return
  end
  local old, nonce = self.account, self.request_nonce
  self.allow_adopt = false
  self.detach()
  if old and nonce then
    self.send(old, "SCHLAGE_STOP_CATALOG", { NONCE = nonce })
  end
  self.account, self.id, self.scope, self.awaiting = account, "", "", false
  self.auto_account = false
  self:save()
  self:refresh()
end

function Selection:choose_lock(label)
  local device = self.lock_labels[label]
  if label ~= Selection.NONE_LOCK and not device then
    return
  end
  if device and self.id == device.id and self.scope == device.scope and self.provider() == self.account then
    return
  end
  self.allow_adopt = false
  self.detach()
  self.id, self.scope = device and device.id or "", device and device.scope or ""
  self:save()
  self.awaiting = false
  self:refresh()
end

function Selection:catalog(source, nonce, data)
  if
    not self.alive
    or source ~= self.account
    or nonce ~= self.request_nonce
    or type(data) ~= "table"
    or type(data.devices) ~= "table"
  then
    return false
  end
  if data.ready ~= true or type(data.scope) ~= "string" or data.scope == "" then
    self.lock_labels = {}
    local selected = self.id ~= "" and "Unavailable selected lock" or Selection.NONE_LOCK
    self.on_lists(
      self.account_items,
      self.account_label,
      selected == Selection.NONE_LOCK and { selected } or { Selection.NONE_LOCK, selected },
      selected
    )
    self.on_status("Waiting for account discovery")
    return true
  end
  self.last_catalog = data
  if self.scope ~= "" and self.scope ~= data.scope then
    self.allow_adopt = false
    self.detach()
    self.id, self.scope, self.pending, self.awaiting = "", "", false, false
    self:save()
  end
  if self.id == "" and not self.allow_adopt and self.provider() > 0 then
    self.detach()
  end
  local choices, names = {}, {}
  for _, device in ipairs(data.devices) do
    if type(device) == "table" and type(device.id) == "string" and type(device.name) == "string" then
      local name = clean(device.name)
      if name == "" then
        name = "Unnamed lock"
      end
      if device.available == true or device.id == self.id then
        choices[#choices + 1] =
          { id = device.id, name = name, available = device.available == true, scope = data.scope }
        names[name] = (names[name] or 0) + 1
      end
    end
  end
  table.sort(choices, function(a, b)
    return a.name == b.name and a.id < b.id or a.name < b.name
  end)
  local labels, selected, found, used =
    { Selection.NONE_LOCK }, Selection.NONE_LOCK, nil, { [Selection.NONE_LOCK] = true }
  self.lock_labels = {}
  for _, device in ipairs(choices) do
    local label = device.name
    if names[label] > 1 then
      label = label .. " [" .. clean(device.id):sub(-8) .. "]"
    end
    local base, n = label, 1
    while used[label] do
      n = n + 1
      label = base .. " (" .. n .. ")"
    end
    used[label] = true
    labels[#labels + 1] = label
    if device.available then
      self.lock_labels[label] = device
    end
    if device.id == self.id and data.scope == self.scope then
      selected, found = label, device
    end
  end
  if self.id ~= "" and not found then
    selected = "Unavailable selected lock"
    labels[#labels + 1] = selected
  end
  self.on_lists(self.account_items, self.account_label, labels, selected)
  if self.id == "" then
    self.on_status(#choices == 0 and "No available locks" or "Select a lock")
  elseif not found or not found.available then
    self.on_status("Selected lock unavailable")
  elseif self.pending and not self.awaiting then
    self.pending, self.awaiting = false, true
    self.on_status("Connecting selected lock")
    self.send(self.account, "SCHLAGE_SELECT_LOCK", { NONCE = self.request_nonce, ID = self.id, SCOPE = self.scope })
  elseif not self.awaiting then
    self.on_status("Selected: " .. found.name)
  end
  return true
end

function Selection:accepted(source, params)
  if
    not self.alive
    or source ~= self.account
    or params.NONCE ~= self.request_nonce
    or params.ID ~= self.id
    or params.SCOPE ~= self.scope
  then
    return false
  end
  self.awaiting, self.pending = false, false
  if params.SUCCESS == "true" then
    self.on_status("Lock selected")
    self.on_selected()
  else
    self.on_status(params.REASON == "already_assigned" and "Lock already assigned" or "Selection failed; refresh locks")
  end
  return true
end

function Selection:accepts(identity)
  if type(identity) == "table" and identity.online ~= true and identity.bolt == nil then
    return true
  end
  if self.id == "" then
    return self.allow_adopt == true
  end
  return type(identity) == "table" and identity.id == self.id and identity.scope == self.scope
end

function Selection:adopt(identity)
  if
    self.allow_adopt
    and self.id == ""
    and not self.awaiting
    and self.provider() == self.account
    and type(identity.id) == "string"
    and type(identity.scope) == "string"
  then
    self.id, self.scope = identity.id, identity.scope
    self.allow_adopt = false
    self:save()
    if self.last_catalog then
      self:catalog(self.account, self.request_nonce, self.last_catalog)
    end
  end
end

return Selection
