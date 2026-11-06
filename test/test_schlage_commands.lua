local T = require("testlib")
local Commands = require("schlage.commands")
local function fixture()
  local e = {
    now = 0,
    events = {},
    writes = {},
    reads = {},
    auth = {},
    outcomes = {},
    traces = {},
    refreshes = 0,
    available = true,
  }
  e.devices = {
    a = { id = "a", supported = true, connected = true, bolt = "locked" },
    b = { id = "b", supported = true, connected = true, bolt = "unlocked" },
  }
  local function schedule(delay, callback)
    local event = { at = e.now + delay, callback = callback }
    e.events[#e.events + 1] = event
    return {
      cancel = function()
        event.cancelled = true
      end,
    }
  end
  function e.advance(target)
    while true do
      local first
      for _, event in ipairs(e.events) do
        if not event.cancelled and event.at <= target and (not first or event.at < first.at) then
          first = event
        end
      end
      if not first then
        break
      end
      first.cancelled, e.now = true, first.at
      first.callback()
    end
    e.now = target
  end
  local account = {
    ensure = function(_, callback, force)
      if force then
        e.refreshes = e.refreshes + 1
      end
      if e.hold_auth then
        e.auth[#e.auth + 1] = callback
      else
        callback({ access_token = "synthetic-token" })
      end
    end,
  }
  local client = { observed_at = { a = 0, b = 0 }, revisions = {} }
  function client:mark_write(id)
    self.revisions[id] = (self.revisions[id] or 0) + 1
  end
  function client:read(id, callback)
    local read = { id = id, callback = callback }
    e.reads[#e.reads + 1] = read
    return {
      cancel = function()
        read.cancelled = true
      end,
    }
  end
  local transport = {
    write = function(_, token, id, locked, callback)
      local write = { id = id, locked = locked, callback = callback, token = token }
      e.writes[#e.writes + 1] = write
      return {
        cancel = function()
          write.cancelled = true
        end,
      }
    end,
  }
  local poller = { blocked_until = 0 }
  function poller:fresh()
    return e.available
  end
  function poller:can_request()
    return e.available and e.now >= self.blocked_until
  end
  function poller:cooldown(err)
    if err and err.category == "rate_limited" then
      self.blocked_until = e.now + (err.retry_after or 60)
    end
  end
  e.client, e.poller = client, poller
  e.commands = Commands.new({
    account = account,
    client = client,
    transport = transport,
    registry = { devices = e.devices },
    poller = poller,
    schedule = schedule,
    now = function()
      return e.now
    end,
    on_device = function(device)
      e.devices[device.id] = device
      client.observed_at[device.id] = e.now
    end,
    on_outcome = function(id, outcome, intent)
      e.outcomes[#e.outcomes + 1] = { id = id, outcome = outcome, intent = intent }
    end,
    on_trace = function(sequence, action, phase, elapsed, detail)
      e.traces[#e.traces + 1] = { sequence, action, phase, elapsed, detail }
    end,
  })
  function e.last(id)
    for i = #e.outcomes, 1, -1 do
      if e.outcomes[i].id == (id or "a") then
        return e.outcomes[i].outcome
      end
    end
  end
  function e.write_reply(index, err)
    e.writes[index or #e.writes].callback(err and nil or {}, err)
  end
  function e.read_reply(index, bolt, err, connected)
    local read = e.reads[index or #e.reads]
    read.callback(
      err and nil or { id = read.id, supported = true, connected = connected ~= false, bolt = bolt or "unknown" },
      err
    )
  end
  return e
end

T.section("Explicit routed dispatch, HTTP acceptance and reported confirmation")
local e = fixture()
e.commands:request("a", "UNLOCK")
T.eq("one explicit write to selected ID", { e.writes[1].id, e.writes[1].locked }, { "a", false })
T.eq("write revision advances before acknowledgement", e.client.revisions.a, 1)
T.eq("in-flight outcome", e.last(), "pending")
T.eq("dispatch does not move the observed bolt", e.devices.a.bolt, "locked")
e.write_reply()
T.eq("acceptance does not confirm", e.last(), "pending")
e.advance(1)
T.eq("first bounded readback", #e.reads, 1)
e.read_reply(nil, "unlocked")
T.eq("reported target confirms", e.last(), "confirmed")
T.eq("observed bolt updates independently", e.devices.a.bolt, "unlocked")
e.advance(100)
T.eq("confirmation stops further reads", #e.reads, 1)

T.section("Known-state toggle, offline, unsupported and unknown targets")
e = fixture()
T.falsy("missing target rejected", e.commands:request("missing", "LOCK"))
e.devices.a.bolt = "unknown"
T.falsy("unknown-state toggle rejected", e.commands:request("a", "TOGGLE"))
T.eq("unknown state outcome", e.last(), "rejected: state_unknown")
e.devices.a.connected = false
T.falsy("disconnected explicit command rejected", e.commands:request("a", "UNLOCK"))
e.devices.a.connected, e.devices.a.supported = true, false
T.falsy("unsupported type rejected", e.commands:request("a", "LOCK"))
T.eq("no writes for rejected targets", #e.writes, 0)
e.devices.a.supported, e.devices.a.bolt = true, "locked"
e.commands:request("a", "TOGGLE")
T.eq("locked toggle resolves to explicit unlock once", e.writes[1].locked, false)

T.section("Generic Door Lock repeated toggles reverse pending targets")
e = fixture()
e.commands:request("a", "TOGGLE")
T.falsy("first tap on a reported locked bolt requests unlock", e.writes[1].locked)
e.advance(0.5)
e.commands:request("a", "TOGGLE")
T.eq("second tap waits for the outstanding write", #e.writes, 1)
e.write_reply(1)
T.eq("second tap dispatches after acknowledgement", #e.writes, 2)
T.truthy("second tap reverses the pending unlock to lock", e.writes[2].locked)
T.eq("pending target never replaces the reported bolt", e.devices.a.bolt, "locked")
e.write_reply(2)
e.commands:request("a", "TOGGLE")
T.falsy("third tap reverses the pending lock back to unlock", e.writes[3].locked)

e = fixture()
e.hold_auth = true
e.commands:request("a", "TOGGLE")
e.commands:request("a", "TOGGLE")
e.auth[1]({ access_token = "synthetic" })
T.eq("double tap during auth coalesces to one mutation", #e.writes, 1)
T.truthy("queued target, not lagging observed state, determines the second toggle", e.writes[1].locked)

e = fixture()
e.hold_auth = true
for _ = 1, 3 do
  e.commands:request("a", "TOGGLE")
end
e.auth[1]({ access_token = "synthetic" })
T.eq("three pending toggles coalesce to one mutation", #e.writes, 1)
T.falsy("third queued toggle requests unlock", e.writes[1].locked)

e = fixture()
e.commands:request("a", "TOGGLE")
e.write_reply(1)
e.devices.a.bolt = "unknown"
T.falsy("pending target never enables toggling an unknown bolt", e.commands:request("a", "TOGGLE"))
T.eq("unknown bolt rejection remains visible", e.last(), "rejected: state_unknown")
T.eq("unknown bolt cannot dispatch another toggle", #e.writes, 1)

e = fixture()
e.commands:request("a", "UNLOCK")
e.write_reply(1, { category = "http_error" })
e.commands:request("a", "TOGGLE")
T.falsy("definitively rejected target is not used as the toggle baseline", e.commands.slots.a.queue.locked)

e = fixture()
e.devices.a.bolt = "unlocked"
e.commands:request("a", "TOGGLE")
e.commands:request("a", "TOGGLE")
e.write_reply(1)
T.falsy("rapid toggles reverse correctly from an initially unlocked bolt", e.writes[2].locked)

e = fixture()
e.hold_auth = true
e.commands:request("a", "TOGGLE")
e.advance(31)
e.commands:request("a", "TOGGLE")
e.auth[1]({ access_token = "synthetic" })
T.falsy("expired queued target cannot reverse a new toggle", e.writes[1].locked)

e = fixture()
e.commands:request("a", "TOGGLE")
e.write_reply(1)
e.advance(31)
e.commands:request("a", "TOGGLE")
T.falsy("expired active target cannot reverse a new toggle", e.writes[2].locked)

T.section("Shared delayed auth, newest unsent intent, strict queue expiry")
e = fixture()
e.hold_auth = true
e.commands:request("a", "UNLOCK")
e.commands:request("a", "LOCK")
T.eq("one pending authentication waiter", #e.auth, 1)
e.advance(5)
e.auth[1]({ access_token = "synthetic" })
T.eq("only newest unsent intent is dispatched", #e.writes, 1)
T.truthy("newest intent is Lock", e.writes[1].locked)
e = fixture()
e.hold_auth = true
e.commands:request("a", "UNLOCK")
e.advance(31)
T.eq("expired unsent unlock reported", e.last(), "expired")
e.auth[1]({ access_token = "synthetic" })
T.eq("late auth cannot dispatch expired unlock", #e.writes, 0)
e = fixture()
e.poller.blocked_until = 60
e.commands:request("a", "UNLOCK")
e.advance(61)
T.eq("no unlock after cooldown exceeds expiry", #e.writes, 0)
T.eq("cooldown queue expires", e.last(), "expired")

T.section("Per-lock serialization, coalescing and independent other locks")
e = fixture()
e.commands:request("a", "UNLOCK")
e.commands:request("a", "LOCK")
e.commands:request("a", "UNLOCK")
e.commands:request("b", "LOCK")
T.eq("other lock can dispatch independently", #e.writes, 2)
e.write_reply(1)
T.eq("next same-lock write follows cloud acknowledgement without waiting for state", #e.writes, 3)
T.eq("superseded confirmation does not issue unnecessary reads", #e.reads, 0)
T.eq("only newest unsent opposite sequence remains", e.writes[3].locked, false)
T.eq("new intent owns displayed outcome", e.last(), "pending")

T.section("Rapid opposite intents serialize writes while superseding old readback")
e = fixture()
e.commands:request("a", "UNLOCK")
e.commands:request("a", "LOCK")
T.eq("second mutation cannot overlap an unacknowledged first write", #e.writes, 1)
e.advance(0.4)
e.write_reply(1)
T.eq("opposite intent dispatches immediately after acknowledgement", #e.writes, 2)
T.truthy("newest explicit target is Lock", e.writes[2].locked)
T.eq("each dispatched write advances stale-read protection", e.client.revisions.a, 2)
T.eq("HTTP acceptance never reports confirmation", e.last(), "pending")
T.eq("queued wait and dispatch timing are recorded", e.traces[#e.traces], { 2, "lock", "dispatched", 400, "" })
e.write_reply(2)
e.advance(1.4)
e.read_reply(nil, "locked")
T.eq("newest command confirms only from a post-write observation", e.last(), "confirmed")
e.advance(40)
T.eq("old deadline cannot change latest outcome", e.last(), "confirmed")
T.eq("opposite intents are single-shot writes", #e.writes, 2)

e = fixture()
e.commands:request("a", "UNLOCK")
e.write_reply(1)
e.advance(1)
T.eq("first confirmation read is active", #e.reads, 1)
e.commands:request("a", "LOCK")
T.eq("new intent does not wait for an old readback", #e.writes, 2)
T.truthy("superseded confirmation read is cancelled", e.reads[1].cancelled)
e.read_reply(1, "unlocked")
T.eq("late superseded read cannot update command state", e.devices.a.bolt, "locked")
T.eq("late superseded read cannot confirm newest intent", e.last(), "pending")

for _, category in ipairs({ "transport_error", "unauthorized", "http_error", "rate_limited" }) do
  e = fixture()
  e.commands:request("a", "UNLOCK")
  e.write_reply(1, { category = category, retry_after = 60 })
  e.commands:request("a", "LOCK")
  T.eq("failed or uncertain write retains serialization barrier: " .. category, #e.writes, 1)
end

T.section("Command timing diagnostics expose no raw protocol values")
e = fixture()
e.commands:request("a", "UNLOCK")
e.advance(0.25)
e.write_reply(1, { category = "sentinel-token-and-device-id" })
T.eq(
  "unknown diagnostic details are filtered",
  e.traces[#e.traces],
  { 1, "unlock", "cloud_failed", 250, "unknown_error" }
)

T.section("Removal, disconnect, restart and authentication callbacks cannot revive intents")
for _, mode in ipairs({ "removal", "disconnect", "restart" }) do
  e = fixture()
  e.hold_auth = true
  e.commands:request("a", "UNLOCK")
  if mode == "removal" then
    e.devices.a = nil
    e.commands:sync()
  elseif mode == "disconnect" then
    e.devices.a.connected = false
    e.commands:sync()
  else
    e.commands:cancel()
  end
  if mode == "disconnect" then
    e.devices.a.connected = true
  end
  e.auth[1]({ access_token = "synthetic" })
  e.advance(100)
  T.eq("lifecycle cancels old unlock: " .. mode, #e.writes, 0)
end

T.section("Jam, missing state, delayed state and absolute deadline")
e = fixture()
e.commands:request("a", "UNLOCK")
e.commands:cancel_device("a")
e.write_reply()
e.advance(60)
T.eq("unbinding cancels transmitted command tracking", e.last(), "cancelled")
T.eq("late acknowledgement after unbind cannot start work", #e.reads, 0)
e = fixture()
e.hold_auth = true
e.commands:request("a", "UNLOCK")
e.commands:cancel_device("a")
e.auth[1]({ access_token = "synthetic" })
T.eq("child restart or unbind drops delayed unsent unlock", #e.writes, 0)
e = fixture()
e.commands:request("a", "UNLOCK")
e.write_reply()
e.advance(1)
e.read_reply(nil, "locked")
e.advance(3)
e.read_reply(nil, "unknown")
T.eq("missing state is not success", e.last(), "pending")
e.advance(7)
e.read_reply(nil, "jammed")
T.eq("jam stops confirmation with fault", e.last(), "fault")
e = fixture()
e.commands:request("a", "UNLOCK")
e.write_reply()
for _, at in ipairs({ 1, 3, 7, 15, 29 }) do
  e.advance(at)
  e.read_reply(nil, "unknown")
end
e.advance(30)
T.eq("unknown state reaches unconfirmed by deadline", e.last(), "unconfirmed")
T.eq("bounded number of reads", #e.reads, 5)
T.eq("only one mutation despite missing state", #e.writes, 1)
e = fixture()
e.commands:request("a", "UNLOCK")
e.advance(15)
e.write_reply(nil, { category = "transport_error" })
e.advance(15.001)
e.read_reply(nil, "unlocked")
T.eq("uncertain timeout reconciles by reading", e.last(), "confirmed")
T.eq("uncertain mutation is never replayed", #e.writes, 1)

T.section("429, 401, uncertain hangs and late response after deadline")
e = fixture()
e.commands:request("a", "UNLOCK")
e.write_reply(nil, { category = "rate_limited", retry_after = 60 })
e.advance(30)
T.eq("rate limit beyond deadline is unconfirmed", e.last(), "unconfirmed")
e.advance(90)
T.eq("no read during cooldown and no late automatic work", #e.reads, 0)
T.eq("rate-limited mutation not replayed", #e.writes, 1)
e = fixture()
e.commands:request("a", "UNLOCK")
e.write_reply(nil, { category = "unauthorized" })
T.eq("401 forces session renewal", e.refreshes, 1)
e.advance(1)
e.read_reply(nil, "unlocked")
T.eq("rejected mutation remains distinct from observed target", e.last(), "rejected")
T.eq("401 mutation not replayed", #e.writes, 1)
e = fixture()
e.commands:request("a", "UNLOCK")
e.advance(30)
T.eq("hung write ends at absolute deadline", e.last(), "unconfirmed")
e.write_reply()
e.advance(60)
T.eq("late write acknowledgement cannot start reads", #e.reads, 0)
e = fixture()
e.commands:request("a", "UNLOCK")
e.write_reply()
e.advance(1)
e.advance(30)
e.read_reply(nil, "unlocked")
T.eq("late physical read cannot restore old command success", e.last(), "unconfirmed")
T.finish()
