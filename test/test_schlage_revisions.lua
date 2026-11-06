require("c4_shim")
local T = require("testlib")
local Client = require("schlage.client")
local JSON = require("JSON"):new({ strictTypes = true })
local lists, reads, now, value, failure = {}, {}, 1
local account = {
  generation = 0,
  ensure = function(_, callback)
    callback({ access_token = "synthetic" })
  end,
}
local transport = {
  devices = function(_, _, callback)
    lists[#lists + 1] = callback
    return { cancel = function() end }
  end,
  device = function(_, _, _, callback)
    reads[#reads + 1] = callback
    return { cancel = function() end }
  end,
}
local client = Client.new(account, transport, function()
  return now
end)
local function result(a, b)
  value, failure = a, b
end
local function raw(state)
  return { deviceId = "a", devicetypeId = "be499wifi", connected = true, attributes = { lockState = state } }
end
local function listing(state)
  return JSON:newArray({ raw(state) })
end
client:discover(result)
lists[1](listing(1))

T.section("Write dispatch invalidates all earlier reads, including uncertain writes")
client:discover(result)
client:mark_write("a")
now = 2
client:read("a", result)
reads[1](raw(0))
T.eq("post-write GET observes unlock", client.devices.a.bolt, "unlocked")
now = 3
lists[2](listing(1))
T.eq("pre-write poll cannot overwrite post-write GET", client.devices.a.bolt, "unlocked")
T.eq("handoff listing retains newer public model", value[1].bolt, "unlocked")
T.eq("stale poll does not refresh device observation time", client.observed_at.a, 2)
client:read("a", result)
client:mark_write("a")
reads[2](raw(1))
T.eq("pre-dispatch GET ignored even when mutation is uncertain", failure.category, "cancelled")
T.eq("uncertain write cannot resurrect earlier state", client.devices.a.bolt, "unlocked")

T.section("Read sequence rejects out-of-order responses within one write revision")
client:read("a", result)
client:read("a", result)
reads[4](raw(1))
reads[3](raw(0))
T.eq("older same-revision read ignored", failure.category, "cancelled")
T.eq("newer same-revision observed bolt retained", client.devices.a.bolt, "locked")

T.section("Removal tombstones, stale empty lists and lifecycle isolation")
client:discover(result)
client:mark_write("a")
lists[3](JSON:newArray({}))
T.truthy("pre-write empty listing cannot remove active target", client.devices.a)
client:read("a", result)
client:discover(result)
lists[4](JSON:newArray({}))
T.eq("new successful empty listing removes device", client.devices.a, nil)
reads[5](raw(1))
T.eq("older GET cannot resurrect removed device", client.devices.a, nil)
client:read("a", result)
account.generation = 1
reads[6](raw(1))
T.eq("account change ignores old device response", failure.category, "cancelled")
T.eq("account change cannot restore device cache", client.devices.a, nil)
T.section("Cooldown is checked again after delayed authentication")
local held, allowed = nil, true
account.ensure = function(_, callback)
  held = callback
end
client.can_request = function()
  return allowed, 60
end
local before_reads, before_lists = #reads, #lists
client:read("a", result)
allowed = false
held({ access_token = "synthetic" })
T.eq("no individual GET leaks through a new cooldown", #reads, before_reads)
T.eq("individual read reports cooldown", failure.category, "rate_limited")
allowed = true
client:discover(result)
allowed = false
held({ access_token = "synthetic" })
T.eq("no listing leaks through a new cooldown", #lists, before_lists)
T.eq("listing reports cooldown", failure.category, "rate_limited")
T.finish()
