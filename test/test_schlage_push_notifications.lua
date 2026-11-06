require("c4_shim")
require("lib.utils")
local T = require("testlib")
local Push = require("schlage.push_notifications")
local now, timers, sends, status = 0, {}, {}, nil
local enabled_agent, valid, mutate, malformed = true, true, true, false
local ecobee =
  "<template><templateid>3</templateid><name>Existing thermostat</name><category>9</category><severity>2</severity><subject>Existing subject</subject><message>Existing message</message><timestamp>1</timestamp><attachments/></template>"
local rows = { [3] = ecobee }
local next_id = 4
local function schedule(seconds, callback)
  local timer = { at = now + seconds, callback = callback }
  timers[#timers + 1] = timer
  return {
    cancel = function()
      timer.cancelled = true
    end,
  }
end
local function advance(seconds)
  local finish = now + seconds
  while true do
    local first
    for _, timer in ipairs(timers) do
      if not timer.cancelled and not timer.done and timer.at <= finish and (not first or timer.at < first.at) then
        first = timer
      end
    end
    if not first then
      break
    end
    now = first.at
    first.done = true
    first.callback()
  end
  now = finish
end
local function read()
  if malformed then
    return "<error>unavailable</error>"
  end
  local list = { "<templates>" }
  for _, row in pairs(rows) do
    list[#list + 1] = row
  end
  list[#list + 1] = "</templates>"
  return table.concat(list)
end
local function send(agent, command, params)
  sends[#sends + 1] = { agent = agent, command = command, params = params }
  if command == "ADD_TEMPLATE" or command == "MODIFY_TEMPLATE" then
    if not mutate then
      return
    end
    local xml = params.TEMPLATE_XML
    local row = ParseXml(xml).template
    local id = tonumber(row.templateid)
    if id == 0 then
      id = next_id
      next_id = next_id + 1
      xml = xml:gsub("<templateid>0</templateid>", "<templateid>" .. id .. "</templateid>")
    end
    schedule(0.35, function()
      rows[id] = xml
    end)
  end
end
local function count(command)
  local n = 0
  for _, call in ipairs(sends) do
    if call.command == command then
      n = n + 1
    end
  end
  return n
end
local function manager()
  return Push.new({
    owner = 42,
    token = function(identity)
      return identity.id
    end,
    agent = function()
      return enabled_agent and 100 or nil
    end,
    read = read,
    send = send,
    now = function()
      return now
    end,
    schedule = schedule,
    valid = function()
      return valid
    end,
    status = function(value)
      status = value
    end,
  })
end
local a, b = { id = "aa", scope = "synthetic-scope" }, { id = "bb", scope = "synthetic-scope" }
T.section("Off by default and isolated from existing notifications")
local push = manager()
T.falsy("automatic push is disabled initially", push:ready())
T.falsy("Off rejects submissions", push:submit(a, "Door A"))
T.eq("Off has no native mutations", #sends, 0)
push:configure(true)
T.eq(
  "enabled submission queues a driver-owned message",
  push:submit(a, "Low battery: Patio & Garage <East> (10%)."),
  "queued"
)
T.eq("one template creation", count("ADD_TEMPLATE"), 1)
T.eq("no send before native configuration is verified", count("SEND_NOTIFICATION"), 0)
advance(0.5)
T.eq("send follows readback of driver-owned message", count("SEND_NOTIFICATION"), 1)
T.eq("existing notification was never altered", rows[3], ecobee)
T.eq("send targets the newly created template, not existing thermostat", sends[#sends].params.TEMPLATE_ID, "4")
T.contains("body retains XML-sensitive device name", ParseXml(rows[4]).template.message, "Patio & Garage <East>")
T.excludes("public entry name excludes raw account scope", ParseXml(rows[4]).template.name, "synthetic-scope")
T.contains("submission status does not claim phone delivery", status, "not confirmed")

T.section("Separate locks cannot overwrite each other's alert text")
push:submit(a, "Updated Patio battery message")
push:submit(b, "Garage battery message")
advance(1)
T.eq("both jobs submitted once", count("SEND_NOTIFICATION"), 3)
T.eq("existing owned message is updated rather than duplicated", count("MODIFY_TEMPLATE"), 1)
T.eq("second physical lock receives a separate entry", count("ADD_TEMPLATE"), 2)
T.eq("first lock retains its own text", ParseXml(rows[4]).template.message, "Updated Patio battery message")
T.eq("second lock retains its own text", ParseXml(rows[5]).template.message, "Garage battery message")
T.eq("unrelated notification remains unchanged", rows[3], ecobee)
local creations = count("ADD_TEMPLATE")
push:stop()
push = manager()
push:configure(true)
push:submit(b, "Garage battery message")
T.eq("restart reuses the existing owned entry", count("ADD_TEMPLATE"), creations)
T.eq("unchanged entry can send without an extra native write", count("SEND_NOTIFICATION"), 4)

T.section("Off, stale data, missing agent and lifecycle cancellation")
push:submit(a, "A message pending configuration")
local submitted = count("SEND_NOTIFICATION")
push:configure(false)
advance(1)
T.eq("Off cancels a queued notification before send", count("SEND_NOTIFICATION"), submitted)
push:configure(true)
push:submit(a, "Another pending message")
valid = false
advance(1)
T.eq("outage or battery recovery cancels pending delivery", count("SEND_NOTIFICATION"), submitted)
valid = true
enabled_agent = false
T.falsy("missing native agent makes readiness false", push:ready())
T.falsy("missing agent cannot queue a notification", push:submit(a, "Ignored"))
enabled_agent = true
push:submit(a, "Destroyed job")
push:stop()
advance(1)
T.eq("destroyed generation cannot resume", count("SEND_NOTIFICATION"), submitted)

T.section("Unconfirmed writes fail closed and malformed reads are sanitized")
push = manager()
push:configure(true)
mutate = false
push:submit(a, "Not applied")
advance(3)
T.eq("unconfirmed native modification never sends an older message", count("SEND_NOTIFICATION"), submitted)
T.contains("unconfirmed setup is visible", status, "not confirmed")
malformed = true
push:submit(a, "No valid template list")
T.eq("malformed native list never sends", count("SEND_NOTIFICATION"), submitted)
T.eq("read failure uses fixed public text", status, "Cannot read Control4 push notifications")
T.finish()
