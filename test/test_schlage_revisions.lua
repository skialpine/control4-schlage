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
T.section("Command confirmation from revision-checked discovery")
local Commands = require("schlage.commands")
local writes, outcome = {}, nil
account.generation, account.destroyed = 0, false
account.ensure = function(_, callback)
  callback({ access_token = "synthetic" })
end
client.can_request = nil
client:cancel()
transport.write = function(_, _, _, _, callback)
  writes[#writes + 1] = callback
  return { cancel = function() end }
end
local registry = { devices = {} }
local poller = { blocked_until = 0 }
function poller:fresh()
  return true
end
function poller:can_request()
  return true
end
function poller:cooldown() end
local commands = Commands.new({
  account = account,
  client = client,
  transport = transport,
  registry = registry,
  poller = poller,
  now = function()
    return now
  end,
  schedule = function()
    return { cancel = function() end }
  end,
  on_outcome = function(_, state)
    outcome = state
  end,
})
local function discover()
  client:discover(function(devices)
    if devices then
      registry.devices = client.devices
      commands:sync()
    end
  end)
  return lists[#lists]
end
discover()(listing(1))
local before_write = discover()
commands:request("a", "LOCK")
writes[#writes]({})
before_write(listing(1))
T.eq("retained matching pre-write state cannot confirm a command", outcome, "pending")
discover()(listing(1))
T.eq("fresh post-write discovery confirms without an individual GET", outcome, "confirmed")

commands:request("a", "UNLOCK")
discover()(listing(0))
T.eq("discovery cannot finish while the write is still in flight", outcome, "pending")
writes[#writes]({})
commands:sync()
T.eq("post-dispatch observation can confirm after acknowledgement", outcome, "confirmed")

commands:request("a", "LOCK")
writes[#writes](nil, { category = "http_error" })
discover()(listing(1))
T.eq("discovery of a target does not turn a rejected write into success", outcome, "rejected")
commands:request("a", "UNLOCK")
writes[#writes](nil, { category = "transport_error" })
discover()(listing(0))
T.eq("uncertain write can be reconciled without mutation replay", outcome, "confirmed")

commands:request("a", "LOCK")
writes[#writes]({})
local superseded = discover()
commands:request("a", "UNLOCK")
writes[#writes]({})
superseded(listing(0))
T.eq("old command's listing cannot confirm a superseding command", outcome, "pending")
discover()(listing(2))
T.eq("fresh discovery jam ends confirmation as a fault", outcome, "fault")
commands:request("a", "UNLOCK")
writes[#writes]({})
local late = discover()
now = now + 31
late(listing(0))
T.eq("discovery past the deadline cannot confirm an old command", outcome, "pending")
commands:cancel()
discover()(listing(0))
T.eq("cancelled command cannot be revived by discovery", outcome, "cancelled")
T.eq("discovery reconciliation never replays a mutation", #writes, 7)
T.finish()
