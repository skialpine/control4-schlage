require("lib.utils")
local persist = require("lib.persist")
local Companion = require("schlage.companion")
local Selection = require("schlage.selection")
local Registry = require("schlage.registry")
local JSON = require("JSON")
local log = require("lib.logging")
local Updates = require("schlage.updates")
local Diagnostics = require("schlage.diagnostics")
local Programming = require("schlage.programming")
local companion, log_timer, selection, updating_selection, update_settings, programming
local proxy_status, proxy_identity

local function publish_lock_status(state)
  local status = state.bolt == "jammed" and "fault" or (state.bolt or "unknown")
  if state.supported == nil then
    -- Selection is being cleared, or no observation has arrived yet. Clear
    -- the cached display without inventing a movement/history event.
    if proxy_status then
      C4:SendToProxy(5001, "LOCK_STATUS_INITIALIZE", { LOCK_STATUS = "unknown" }, "NOTIFY")
    end
    proxy_status, proxy_identity = nil, nil
    return
  end
  local identity = companion and companion.identity or {}
  local initialize = not proxy_identity or proxy_identity.id ~= identity.id or proxy_identity.scope ~= identity.scope
  if initialize or proxy_status ~= status then
    local command = initialize and "LOCK_STATUS_INITIALIZE" or "LOCK_STATUS_CHANGED"
    local params = { LOCK_STATUS = status }
    if not initialize then
      params.LAST_ACTION_DESCRIPTION = "Reported lock state: " .. status
      params.SOURCE = "Schlage Home"
      local requested = status == "locked" and "lock" or "unlock"
      local commanded = state.outcome == "pending" and state.intent == requested
      -- Mark observations outside a matching pending Control4 command as
      -- external to that command. REST cannot identify the actual actor or
      -- distinguish thumbturn, keypad, Schlage app, and another automation.
      params.MANUAL = state.online == true and (status == "locked" or status == "unlocked") and not commanded
    end
    log:info("Schlage lock proxy status: %s (%s; manual=%s)", status, command, tostring(params.MANUAL))
    C4:SendToProxy(5001, command, params, "NOTIFY")
  end
  proxy_status = status
  proxy_identity = { id = identity.id, scope = identity.scope }
end

local function configure_logging()
  log:setLogLevel(Properties["Log Level"] or "3 - Info")
  log:setLogMode(Properties["Log Mode"] or "Off")
  -- Preserve structured Ultra logging without raw companion message dumps.
  DEBUGPRINT, DEBUG_URL, DEBUG_RFN, DEBUG_WEBSOCKET, DEBUG_TIMER = false, false, false, false, false
  if log_timer then
    log_timer:Cancel()
    log_timer = nil
  end
  if log:isEnabled() then
    log_timer = C4:SetTimer(3 * 60 * 60 * 1000, function()
      log_timer = nil
      log:setLogMode("Off")
      C4:UpdateProperty("Log Mode", "Off")
    end)
  end
end

local function provider()
  return tonumber(C4:GetBoundProviderDevice(C4:GetDeviceID(), Registry.INPUT)) or 0
end

local function present(state)
  if programming then
    programming:update(state, companion and companion.identity)
  end
  C4:UpdateProperty("Driver Status", state.online and "Online" or "Offline")
  C4:UpdateProperty("Bolt State", state.bolt or "unknown")
  C4:UpdateProperty("Lock Name", state.name or "")
  C4:UpdateProperty("Lock Model", state.model or "")
  C4:UpdateProperty("Battery", state.battery ~= nil and (tostring(state.battery) .. "%") or "Not provided")
  C4:UpdateProperty("Low Battery", state.low_battery == nil and "Not provided" or (state.low_battery and "Yes" or "No"))
  C4:UpdateProperty(
    "Last Update",
    state.updated_at and os.date("%Y-%m-%d %H:%M:%S %Z", state.updated_at) or "Not observed"
  )
  C4:UpdateProperty("Command Outcome", state.outcome or "none")
  C4:SetVariable("ONLINE", state.online and "1" or "0")
  C4:SetVariable("BOLT_STATE", state.bolt or "unknown")
  C4:SetVariable("JAMMED", state.fault and "1" or "0")
  C4:SetVariable("BATTERY_PERCENT", state.battery ~= nil and tostring(math.floor(state.battery)) or "-1")
  C4:SetVariable("BATTERY_KNOWN", state.battery ~= nil and "1" or "0")
  C4:SetVariable(
    "LOW_BATTERY_STATE",
    state.low_battery == nil and "unknown" or (state.low_battery and "low" or "normal")
  )
  C4:SetVariable(
    "LAST_SUCCESSFUL_UPDATE",
    state.updated_at and os.date("!%Y-%m-%d %H:%M:%S UTC", state.updated_at) or ""
  )
  C4:SetVariable("COMMAND_OUTCOME", state.outcome or "none")
  C4:SetVariable("REQUESTED_ACTION", state.intent or "")
  C4:SendToProxy(5001, "ONLINE_CHANGED", { STATE = state.online == true }, "NOTIFY")
  publish_lock_status(state)
end

local function intent(action)
  if not companion then
    return
  end
  local reason
  if not companion.state.online then
    reason = "offline"
  elseif action == "TOGGLE" and companion.state.bolt ~= "locked" and companion.state.bolt ~= "unlocked" then
    reason = "state_unknown"
  end
  if reason then
    log:info("Schlage lock command rejected: %s", reason)
    companion.state.outcome = "rejected: " .. reason
    companion.state.intent = action == "LOCK" and "lock" or (action == "UNLOCK" and "unlock" or "")
    present(companion.state)
    return
  end
  C4:SendToProxy(
    Registry.INPUT,
    "LOCK_INTENT",
    { CHILD = tostring(C4:GetDeviceID()), NONCE = companion.subscription, ACTION = action },
    "NOTIFY"
  )
end

function OnDriverInit()
  proxy_status, proxy_identity = nil, nil
  update_settings = nil
  programming = nil
  if selection then
    selection.alive = false
    selection = nil
  end
  if log_timer then
    log_timer:Cancel()
    log_timer = nil
  end
  log:setLogName("Schlage Lock")
  companion = nil
  for _, variable in ipairs({
    { "ONLINE", "0", "BOOL" },
    { "BOLT_STATE", "unknown", "STRING" },
    { "JAMMED", "0", "BOOL" },
    { "BATTERY_PERCENT", "-1", "INT" },
    { "BATTERY_KNOWN", "0", "BOOL" },
    { "LOW_BATTERY_STATE", "unknown", "STRING" },
    { "LAST_SUCCESSFUL_UPDATE", "", "STRING" },
    { "COMMAND_OUTCOME", "none", "STRING" },
    { "REQUESTED_ACTION", "", "STRING" },
  }) do
    C4:AddVariable(variable[1], variable[2], variable[3], true, false)
  end
end

function OnDriverLateInit()
  C4:UpdateProperty("Driver Status", "Initializing")
  configure_logging()
  programming = Programming.new()
  programming:start()
  update_settings = Updates.settings()
  update_settings:sync()
  companion = Companion.new({
    persist = persist,
    provider = provider,
    nonce = function()
      return C4:UUID("RANDOM")
    end,
    send = function(nonce)
      C4:SendToProxy(Registry.INPUT, "REFRESH_STATE", { CHILD = tostring(C4:GetDeviceID()), NONCE = nonce }, "NOTIFY")
    end,
    on_state = present,
    accepts = function(data)
      return not selection or (selection.account == provider() and selection:accepts(data))
    end,
    on_identity = function(identity)
      if selection then
        selection:adopt(identity)
      end
    end,
  })
  selection = Selection.new({
    store = persist,
    provider = provider,
    identity = function()
      return companion.identity
    end,
    accounts = function()
      return C4:GetDevicesByC4iName("schlage_account.c4z") or {}
    end,
    nonce = function()
      return C4:UUID("RANDOM")
    end,
    send = function(account, command, params)
      params.CHILD = tostring(C4:GetDeviceID())
      C4:SendToDevice(account, command, params, true, false)
    end,
    detach = function()
      local old = provider()
      if old > 0 and companion.subscription then
        C4:SendToDevice(
          old,
          "SCHLAGE_RELEASE_LOCK",
          { CHILD = tostring(C4:GetDeviceID()), NONCE = companion.subscription },
          true,
          false
        )
      end
      C4:Unbind(C4:GetDeviceID(), Registry.INPUT)
      companion:suspend()
    end,
    on_lists = function(accounts, account, locks, lock)
      updating_selection = true
      C4:UpdatePropertyList("Schlage Account", table.concat(accounts, ","), account)
      C4:UpdatePropertyList("Lock", table.concat(locks, ","), lock)
      updating_selection = false
    end,
    on_status = function(value)
      C4:UpdateProperty("Selection Status", value)
    end,
    on_selected = function()
      companion:refresh()
    end,
  })
  selection:refresh()
  C4:UpdateProperty("Driver Version", C4:GetDriverConfigInfo("version"))
  companion:refresh()
end

function OnBindingChanged(binding)
  if binding == Registry.INPUT and companion then
    companion:refresh()
  elseif binding == 5001 and companion then
    proxy_status, proxy_identity = nil, nil
    present(companion.state)
  end
end

function ExecuteCommand(command, params)
  if command == "LUA_ACTION" then
    command = params and params.ACTION
  end
  params = params or {}
  if update_settings and update_settings:execute(command, params) then
    return
  end
  if command == "Diagnostics_Snapshot" then
    local state = companion and companion.state or {}
    print(Diagnostics.render({
      role = "lock",
      version = C4:GetDriverConfigInfo("version"),
      os_version = (C4:GetVersionInfo() or {}).version,
      online = state.online,
      bolt = state.bolt,
      battery_percent = state.battery,
      low_battery = state.low_battery,
      selected = selection and selection.id ~= "" or false,
      outcome = state.outcome,
      log_mode = Properties["Log Mode"],
      log_level = log:getLogLevel(),
      automatic_updates = update_settings and update_settings:get("Automatic Updates"),
      update_channel = update_settings and update_settings:get("Update Channel"),
    }))
    return
  end
  if not companion then
    return
  end
  if command == "LOCK" or command == "UNLOCK" or command == "TOGGLE" then
    intent(command)
    return
  end
  if command == "Refresh_State" then
    companion:refresh()
  elseif command == "Refresh_Available_Locks" then
    selection:refresh()
  elseif command == "SCHLAGE_CATALOG_CHANGED" then
    if not selection.account or tonumber(params.SOURCE) == selection.account then
      selection:refresh()
    end
  elseif command == "SCHLAGE_CATALOG" then
    local ok, value = pcall(JSON.decode, JSON, params.JSON or "")
    if ok then
      selection:catalog(tonumber(params.SOURCE), params.NONCE, value)
    end
  elseif command == "SCHLAGE_SELECTED" then
    selection:accepted(tonumber(params.SOURCE), params)
  elseif command == "SCHLAGE_IDENTIFY" then
    local source = tonumber(params.SOURCE)
    -- This is a public identity census, never an authentication exchange.
    if source and type(params.NONCE) == "string" then
      C4:SendToDevice(source, "SCHLAGE_IDENTITY", {
        CHILD = tostring(C4:GetDeviceID()),
        NONCE = params.NONCE,
        SCOPE = companion.identity.scope or "",
        ID = companion.identity.id or "",
      }, true, false)
    end
  elseif command == "SCHLAGE_ACCOUNT_RESET" and tonumber(params.SOURCE) == provider() then
    selection:refresh()
    companion:refresh()
  elseif command == "SCHLAGE_SNAPSHOT" then
    local ok, value = pcall(JSON.decode, JSON, params.JSON or "")
    if ok then
      companion:take(tonumber(params.SOURCE), params.NONCE, value)
    end
  end
end

function OnDriverDestroyed()
  update_settings = nil
  programming = nil
  if selection then
    selection.alive = false
    if selection.account and selection.request_nonce then
      C4:SendToDevice(
        selection.account,
        "SCHLAGE_STOP_CATALOG",
        { CHILD = tostring(C4:GetDeviceID()), NONCE = selection.request_nonce },
        true,
        false
      )
    end
    selection = nil
  end
  if log_timer then
    log_timer:Cancel()
    log_timer = nil
  end
  if companion then
    present({ online = false })
  end
  companion = nil
end

function OnPropertyChanged(property)
  if update_settings and update_settings:changed(property) then
    return
  end
  if selection and not updating_selection then
    if property == "Schlage Account" then
      selection:choose_account(Properties[property])
      return
    end
    if property == "Lock" then
      selection:choose_lock(Properties[property])
      return
    end
  end
  if companion and (property == "Log Mode" or property == "Log Level") then
    configure_logging()
  end
end

function ReceivedFromProxy(binding, command)
  if binding == 5001 and (command == "LOCK" or command == "UNLOCK" or command == "TOGGLE") then
    log:info("Schlage lock proxy command received: %s", command)
    intent(command)
  end
end
