require("lib.utils")
local log = require("lib.logging")
local persist = require("lib.persist")
local Config = require("schlage.config")
local Transport = require("schlage.transport")
local Cognito = require("schlage.cognito")
local Account = require("schlage.account")
local Client = require("schlage.client")
local redact = require("schlage.redact")
local SRP = require("schlage.cognito_srp")
local bindings = require("lib.bindings")
local Bridge = require("schlage.bridge")
local Poller = require("schlage.poller")
local Commands = require("schlage.commands")
local Updates = require("schlage.updates")
local Diagnostics = require("schlage.diagnostics")
local crypto = require("crypto")
local bytes = require("crypto.utils").bytes
local account, client, log_timer, bridge, poller, commands, updater, update_settings
local function monotonic()
  return C4:GetTickCount() / 1000
end

local function schedule(seconds, callback)
  local timer = C4:SetTimer(math.max(1, math.floor(seconds * 1000)), callback)
  return {
    cancel = function()
      timer:Cancel()
    end,
  }
end

local function status(category)
  category = redact.category(category)
  C4:UpdateProperty("Driver Status", category)
  C4:UpdateProperty("Credentials", account and account:credential_status() or "Unavailable")
  log:info("Schlage account status: %s", category)
end

local function empty_discovery()
  if commands then
    commands:cancel()
  end
  if poller then
    poller:stop()
  end
  if bridge then
    bridge:invalidate()
  end
  if client then
    client:cancel()
  end
  C4:UpdateProperty("Discovered Locks", "Not retrieved")
  C4:UpdateProperty("Last Session Renewal", "Not yet observed")
  C4:UpdateProperty("Polling Status", "Waiting for sign in")
end

local function discovery_text(value, fallback)
  if value == "" then
    return fallback
  end
  -- Print only public fields, on one line per lock. Never print a response table.
  return value:gsub("[%z\1-\31\127]", " "):sub(1, 120)
end

local function report_discovery(devices, err, show_details)
  if err then
    if err.category ~= "cancelled" then
      C4:UpdateProperty("Discovered Locks", "Retrieval failed: " .. redact.category(err.category))
      if show_details then
        print("Schlage discovery failed: " .. redact.category(err.category))
      end
    end
    return
  end
  local summary = #devices .. (#devices == 1 and " lock found" or " locks found")
  C4:UpdateProperty("Discovered Locks", summary)
  log:info("Schlage discovery returned %d devices", #devices)
  if show_details then
    -- An explicit installer action prints even when diagnostic Log Mode is Off.
    local listing = { "Schlage discovery: " .. summary }
    for i, device in ipairs(devices) do
      listing[#listing + 1] = string.format(
        "  %d. %s | type=%s | model=%s%s",
        i,
        discovery_text(device.name, "Unnamed lock"),
        discovery_text(device.device_type, "Unknown"),
        discovery_text(device.model, "Not provided"),
        device.supported and "" or " | unsupported"
      )
    end
    -- One output call keeps the heading and rows together in Composer.
    print(table.concat(listing, "\n"))
  end
end

local function discover(show_details)
  if poller then
    poller:refresh(show_details and function(devices, err)
      report_discovery(devices, err, true)
    end or nil)
  end
end

local function configure_logging()
  Transport.quiet()
  log:setLogLevel(Properties["Log Level"])
  log:setLogMode(Properties["Log Mode"])
  if log_timer then
    log_timer:Cancel()
    log_timer = nil
  end
  if log:isEnabled() then
    log_timer = C4:SetTimer(3 * 60 * 60 * 1000, function()
      log_timer = nil
      log:setLogMode("Off")
      C4:UpdateProperty("Log Mode", "Off")
      Transport.quiet()
    end)
  end
end

function OnDriverInit()
  if updater then
    updater:stop()
  end
  updater, update_settings = nil, nil
  if bridge then
    bridge.children = {}
  end
  if commands then
    commands:cancel()
    commands = nil
  end
  if poller then
    poller:stop()
  end
  if bridge then
    bridge:destroy(true)
    bridge = nil
  end
  if account then
    account:destroy()
  end
  if client then
    client:cancel()
  end
  if log_timer then
    log_timer:Cancel()
    log_timer = nil
  end
  account, client = nil, nil
  poller, bridge = nil, nil
  Transport.quiet()
  log:setLogName("Schlage Account")
  C4:UpdateProperty("Driver Status", "initializing")
  C4:UpdateProperty("Credentials", "Loading")
  C4:UpdateProperty("Last Session Renewal", "Not yet observed")
  bindings:restoreBindings()
end

function OnDriverLateInit()
  configure_logging()
  if updater then
    updater:stop()
  end
  update_settings = Updates.settings()
  updater = Updates.new({
    schedule = schedule,
    setting = function(name)
      return update_settings:get(name)
    end,
    busy = function()
      for _, slot in pairs(commands and commands.slots or {}) do
        if slot.active or slot.queue or slot.preparing then
          return true
        end
      end
      return false
    end,
    status = function(value)
      C4:UpdateProperty("Update Status", value)
    end,
    checked = function(epoch)
      C4:UpdateProperty("Last Update Check", os.date("%Y-%m-%d %H:%M:%S %Z", epoch))
    end,
    announce = function(value)
      print("Schlage updates: " .. value)
    end,
  })
  update_settings:sync()
  updater:start()
  if commands then
    commands:cancel()
    commands = nil
  end
  if poller then
    poller:stop()
  end
  if bridge then
    bridge:destroy()
  end
  if account then
    account:destroy()
  end
  bridge = Bridge.new({
    bindings = bindings,
    schedule = schedule,
    nonce = function()
      return C4:UUID("RANDOM")
    end,
    read_time = function(id)
      return client and client.observed_epoch[id]
    end,
  })
  local transport = Transport.new(Config)
  local cognito = Cognito.new({
    config = Config,
    transport = transport,
    metric = function(name, elapsed)
      -- Fixed metric names, numeric durations only. No protocol values are logged.
      C4:UpdateProperty(name == "srp_public_ms" and "SRP Public Time (ms)" or "SRP Proof Time (ms)", tostring(elapsed))
    end,
  })
  local ok, value = pcall(Account.new, {
    config = Config,
    store = persist,
    cognito = cognito,
    schedule = schedule,
    on_status = status,
    on_refreshed = function(epoch)
      C4:UpdateProperty("Last Session Renewal", os.date("%Y-%m-%d %H:%M:%S %Z", epoch))
    end,
    on_ready = function()
      if poller then
        poller:start()
      end
    end,
    on_invalidate = empty_discovery,
  })
  if not ok then
    status("storage_error")
    return
  end
  account = value
  client = Client.new(account, transport, monotonic)
  poller = Poller.new({
    now = monotonic,
    client = client,
    schedule = schedule,
    on_result = function(devices, err)
      report_discovery(devices, err, false)
      C4:UpdateProperty(
        "Polling Status",
        devices and "Read succeeded" or ("Read failed: " .. redact.category(err and err.category))
      )
      if devices and account.session then
        local scope = bytes.to_hex(crypto.sha256.sha256(Config.pool_id .. "\0" .. account.session.username))
        bridge:ingest(scope, devices)
        if commands then
          commands:sync()
        end
      end
    end,
    on_stale = function()
      bridge:stale()
      if commands then
        commands:sync()
      end
      C4:UpdateProperty("Polling Status", "Stale: locks offline")
    end,
  })
  client.can_request = function()
    return poller:can_request(), math.max(0, poller.blocked_until - monotonic())
  end
  commands = Commands.new({
    now = monotonic,
    account = account,
    client = client,
    transport = transport,
    registry = bridge.registry,
    poller = poller,
    schedule = schedule,
    on_outcome = function(id, outcome, intent)
      bridge:outcome(id, outcome, intent)
    end,
    on_trace = function(sequence, action, phase, elapsed, detail)
      log:info("Schlage command %d %s: %s at %d ms %s", sequence, action, phase, elapsed, detail)
    end,
  })
  bridge.on_command = function(id, action)
    commands:request(id, action)
  end
  bridge.on_unbind = function(id)
    commands:cancel_device(id)
  end
  client.on_device = function(device)
    bridge:update(device)
  end
  poller:set_interval(Properties["Polling Interval (seconds)"])
  bridge:reset_children()
  C4:UpdateProperty("Driver Version", C4:GetDriverConfigInfo("version"))
  -- Plaintext Composer values left by an interrupted entry are moved into
  -- protected persistence before being cleared, without generic handler logging.
  OnPropertyChanged("Schlage Email")
  OnPropertyChanged("Schlage Password")
  account:start()
end

function OnPropertyChanged(property)
  Transport.quiet()
  if update_settings and update_settings:changed(property) then
    if updater then
      updater:configure()
    end
    return
  end
  if property == "Polling Interval (seconds)" and poller then
    poller:set_interval(Properties[property])
    C4:UpdateProperty(property, tostring(poller.interval))
    return
  end
  if property == "Log Level" or property == "Log Mode" then
    if account then
      configure_logging()
    end
    return
  end
  local field = property == "Schlage Email" and "username" or property == "Schlage Password" and "password"
  if not field or not account then
    return
  end
  local value = Properties[property]
  if type(value) ~= "string" or value == "" then
    return
  end
  local ok = pcall(account.enter, account, field, value)
  value = nil
  C4:UpdateProperty(property, "")
  if not ok then
    status("storage_error")
  end
end

function ExecuteCommand(command, params)
  Transport.quiet()
  if command == "LUA_ACTION" then
    command = params and params.ACTION
  end
  if update_settings and update_settings:execute(command, params) then
    if command == "SET_UPDATE_SETTING" and updater then
      updater:configure()
    end
    return
  end
  if command == "Check_for_Updates" and updater then
    updater:check(true)
    return
  end
  if command == "Diagnostics_Snapshot" then
    local active, queued, count = 0, 0, 0
    for _, slot in pairs(commands and commands.slots or {}) do
      active = active + (slot.active and 1 or 0)
      queued = queued + (slot.queue and 1 or 0)
    end
    for _ in pairs(bridge and bridge.registry.devices or {}) do
      count = count + 1
    end
    print(Diagnostics.render({
      role = "account",
      version = C4:GetDriverConfigInfo("version"),
      os_version = (C4:GetVersionInfo() or {}).version,
      signed_in = account and account.session ~= nil or false,
      lock_count = count,
      active_commands = active,
      queued_commands = queued,
      polling_interval = poller and poller.interval,
      polling_fresh = poller and poller:fresh() or false,
      srp_public_ms = Properties["SRP Public Time (ms)"],
      srp_proof_ms = Properties["SRP Proof Time (ms)"],
      automatic_updates = update_settings and update_settings:get("Automatic Updates"),
      update_channel = update_settings and update_settings:get("Update Channel"),
      log_mode = Properties["Log Mode"],
      log_level = log:getLogLevel(),
    }))
    return
  end
  if bridge and bridge:execute(command, params) then
    return
  end
  if not account then
    return
  end
  local ok = pcall(function()
    if command == "Sign_In" then
      account:sign_in()
    elseif command == "Sign_Out" then
      account:sign_out()
    elseif command == "Discover_Locks" then
      discover(true)
    elseif command == "Renew_Session" then
      print("Schlage session renewal requested.")
      local modes = { Off = true, Print = true, Log = true, ["Print and Log"] = true }
      local mode = Properties["Log Mode"]
      print(
        string.format(
          "Schlage logging: mode=%s; level=%s; print=%s; log=%s",
          modes[mode] and mode or "Unknown",
          log.LevelToName[log:getLogLevel()] or "Unknown",
          tostring(log:isPrintEnabled()),
          tostring(log:isC4LogEnabled())
        )
      )
      account:ensure(function(_, err)
        if err then
          print("Schlage session renewal failed: " .. redact.category(err.category))
        else
          print("Schlage session renewal succeeded.")
        end
      end, true)
    elseif command == "Check_Crypto" then
      local ready, reason = SRP.ready()
      C4:UpdateProperty("Crypto Status", ready and "Native acceleration and secure randomness available" or reason)
    end
  end)
  if not ok then
    status("unknown_error")
  end
end

function OnDriverDestroyed()
  if updater then
    updater:stop()
  end
  updater, update_settings = nil, nil
  if commands then
    commands:cancel()
    commands = nil
  end
  if poller then
    poller:stop()
  end
  if bridge then
    bridge:destroy()
  end
  if account then
    account:destroy()
  end
  if client then
    client:cancel()
  end
  if log_timer then
    log_timer:Cancel()
    log_timer = nil
  end
  account, client = nil, nil
  poller, bridge = nil, nil
  Transport.quiet()
end

function ReceivedFromProxy(binding, command, params)
  if bridge then
    bridge:request(binding, command, params)
  end
end

function OnBindingChanged(binding, _, bound)
  if bridge and not bound then
    bridge.catalog:publish()
    local _, id = bridge.registry:device_for_binding(binding)
    if commands then
      commands:cancel_device(id)
    end
    for child, subscription in pairs(bridge.children) do
      if subscription.binding == binding and not bridge:is_bound(binding, child) then
        bridge.children[child] = nil
      end
    end
  end
end
