require("c4_shim")
local T = require("testlib")
local Updates = require("schlage.updates")
local deferred = require("deferred")

local function fixture()
  local e = { now = 0, events = {}, calls = {}, statuses = {}, announcements = {}, enabled = "On", channel = "Stable" }
  e.manager = Updates.new({
    filenames = { "schlage_account.c4z", "schlage_lock.c4z" },
    id = 31,
    coordinator = function()
      return e.leader or 31
    end,
    setting = function(name)
      return name == "Automatic Updates" and e.enabled or e.channel
    end,
    busy = function()
      return e.busy == true
    end,
    status = function(value)
      e.statuses[#e.statuses + 1] = value
    end,
    announce = function(value)
      e.announcements[#e.announcements + 1] = value
    end,
    checked = function()
      e.checked = (e.checked or 0) + 1
    end,
    send = function(id, command)
      e.forwarded = { id, command }
    end,
    schedule = function(delay, callback)
      local event = { at = e.now + delay, callback = callback }
      e.events[#e.events + 1] = event
      return {
        cancel = function()
          event.cancelled = true
        end,
      }
    end,
    github = {
      updateAll = function(_, repo, names, prerelease, force)
        local call = { repo = repo, names = names, prerelease = prerelease, force = force, result = deferred.new() }
        e.calls[#e.calls + 1] = call
        return call.result
      end,
    },
  })
  function e.advance(target)
    while true do
      local next_event
      for _, event in ipairs(e.events) do
        if not event.cancelled and event.at <= target and (not next_event or event.at < next_event.at) then
          next_event = event
        end
      end
      if not next_event then
        break
      end
      e.now, next_event.cancelled = next_event.at, true
      next_event.callback()
    end
    e.now = target
  end
  function e.last()
    return e.statuses[#e.statuses]
  end
  return e
end

T.section("Stable automatic updates start after boot and repeat at a bounded interval")
local e = fixture()
e.manager:start()
e.advance(59)
T.eq("no request during startup", #e.calls, 0)
e.advance(60)
T.eq("one update flight", #e.calls, 1)
T.eq("only the project's GitHub releases are queried", e.calls[1].repo, "skialpine/control4-schlage")
T.falsy("stable excludes prereleases", e.calls[1].prerelease)
T.falsy("automatic checks never force a reinstall or downgrade", e.calls[1].force)
e.manager:check(true)
T.eq("manual action joins an in-flight check", #e.calls, 1)
T.eq("repeat manual action has visible feedback", e.announcements[#e.announcements], "Update check already in progress")
e.calls[1].result:resolve({})
T.eq("successful empty result has lasting feedback", e.last(), "Up to date")
e.advance(21659)
T.eq("checks are not continuous", #e.calls, 1)
e.advance(21660)
T.eq("next automatic check is six hours later", #e.calls, 2)

T.section("Off, prerelease, command deferral, and the account coordinator")
e = fixture()
e.enabled = "Off"
e.channel = "Prerelease"
e.manager:start()
e.advance(100)
T.eq("Off disables scheduled checking", #e.calls, 0)
e.manager:check(true)
T.eq("manual check works while automatic checking is Off", #e.calls, 1)
T.truthy("prerelease is an explicit selection", e.calls[1].prerelease)
e.calls[1].result:resolve({ "schlage_lock.c4z" })
T.eq("manual install result is visible", e.last(), "Installing updated drivers")
e.advance(30000)
T.eq("manual check does not enable automatic checks", #e.calls, 1)
e = fixture()
e.busy = true
e.manager:start()
e.advance(60)
T.eq("pending lock command delays automatic update", #e.calls, 0)
T.eq("the reason is visible", e.last(), "Waiting for lock commands")
e.busy = false
e.advance(65)
T.eq("idle coordinator resumes after five seconds", #e.calls, 1)
e = fixture()
e.leader = 12
e.manager:start()
e.advance(60)
T.eq("other account does not duplicate downloads", #e.calls, 0)
e.manager:check(true)
T.eq("manual check forwards to one coordinator", e.forwarded, { 12, "Check_for_Updates" })

T.section("Failures and teardown never expose errors or revive timers")
e = fixture()
e.manager:start()
e.advance(60)
e.calls[1].result:reject({ body = "SENTINEL-TOKEN", error = "SENTINEL-PASSWORD" })
T.contains("failure leaves a readable status", e.last(), "Update check failed")
T.excludes("raw error data is not shown", table.concat(e.statuses, " "), "SENTINEL")
e.manager:stop()
e.advance(50000)
T.eq("destroyed coordinator has no future checks", #e.calls, 1)
e = fixture()
e.manager:start()
e.advance(60)
e.manager:stop()
local before = #e.statuses
e.calls[1].result:resolve({ "schlage_account.c4z" })
T.eq("late completion cannot change destroyed driver's status", #e.statuses, before)
e.advance(50000)
T.eq("late completion cannot reschedule updates", #e.calls, 1)
e = fixture()
e.manager:start()
e.advance(60)
e.calls[1].result:reject("repo skialpine/control4-schlage does not have any valid releases")
T.eq("stable channel with only prereleases has a specific status", e.last(), "No release available in this channel")

T.section("Shared settings use the template without echo loops")
Properties["Automatic Updates"], Properties["Update Channel"] = "On", "Stable"
local shares, takes, settings = {}, {}, nil
settings = Updates.settings({
  filenames = { "schlage_account.c4z", "schlage_lock.c4z" },
  shared = {
    share = function(_, name, value, names)
      shares[#shares + 1] = { name, value, #names }
    end,
    take = function(_, params)
      takes[#takes + 1] = params
      Properties[params.Name] = params.Value
      settings:changed(params.Name) -- simulate Composer's property callback
    end,
  },
})
Properties["Automatic Updates"] = "Off"
settings:changed("Automatic Updates")
T.eq("user change goes to the template sharing helper", shares[1], { "Automatic Updates", "Off", 2 })
settings:execute("SET_UPDATE_SETTING", { Name = "Update Channel", Value = "Prerelease" })
T.eq("received setting takes effect", settings:get("Update Channel"), "Prerelease")
T.eq("received setting is not rebroadcast", #shares, 1)
settings:execute("SET_UPDATE_SETTING", { Name = "Update Channel", Value = "SENTINEL" })
settings:execute("SET_UPDATE_SETTING", { Name = "Schlage Password", Value = "SENTINEL" })
T.eq("unsupported settings and values are ignored", #takes, 1)
T.eq("valid channel remains selected", settings:get("Update Channel"), "Prerelease")

local sent = {}
function C4:GetDeviceID()
  return 44
end
function C4:GetDevicesByC4iName(name)
  return name == "schlage_account.c4z" and { [31] = "Account", [40] = "Second account" } or { [44] = "Lock" }
end
function C4:SendToDevice(id, command, params)
  sent[#sent + 1] = { id, command, params }
end
settings:sync()
T.eq("new companion asks the lowest account for settings", sent[1][1], 31)
T.eq("startup settings request is explicit", sent[1][2], "SCHLAGE_GET_UPDATE_SETTINGS")
settings:execute("SCHLAGE_GET_UPDATE_SETTINGS", { SOURCE = "44" })
T.eq("verified Schlage peer receives both settings", #sent, 3)
settings:execute("SCHLAGE_GET_UPDATE_SETTINGS", { SOURCE = "999" })
T.eq("unrelated device does not get a settings response", #sent, 3)

T.section("Controller fallback still installs the account last")
local stock = require("lib.github-updater")
local saved_download, saved_filename = stock.downloadOutdatedDrivers, C4.GetDriverFileName
stock.downloadOutdatedDrivers = function()
  return deferred.new():resolve({ "schlage_account.c4z", "schlage_lock.c4z" })
end
C4.GetDriverFileName = nil
local tcp = require("c4_fixtures").captureTcpClient({ holdReplies = true })
local result
Updates.release_updater()
  :updateAll("skialpine/control4-schlage", { "schlage_account.c4z", "schlage_lock.c4z" }, false, false)
  :next(function(value)
    result = value
  end)
T.contains("companion is first without GetDriverFileName", tcp.writes[1], "schlage_lock.c4z")
T.eq("update waits for companion reply", #tcp.writes, 1)
tcp.reply()
T.contains("account is sent only after companion reply", tcp.writes[2], "schlage_account.c4z")
tcp.reply()
T.eq("both installed files finish in the fallback path", #result, 2)
tcp.restore()
stock.downloadOutdatedDrivers, C4.GetDriverFileName = saved_download, saved_filename
T.finish()
