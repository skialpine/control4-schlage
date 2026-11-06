local T = require("testlib")
local Selection = require("schlage.selection")
local function fixture(saved, accounts)
  local e = {
    accounts = accounts or { [11] = "Schlage Account" },
    provider = 0,
    sent = {},
    serial = 0,
    saved = saved,
    detached = 0,
    accepted = 0,
  }
  e.selection = Selection.new({
    store = {
      get = function()
        return e.saved or {}
      end,
      set = function(_, _, value)
        e.saved = value
      end,
    },
    accounts = function()
      return e.accounts
    end,
    identity = function()
      return {}
    end,
    provider = function()
      return e.provider
    end,
    nonce = function()
      e.serial = e.serial + 1
      return "request-" .. e.serial
    end,
    send = function(source, command, params)
      e.sent[#e.sent + 1] = { source = source, command = command, params = params }
    end,
    detach = function()
      e.detached = e.detached + 1
      e.provider = 0
    end,
    on_lists = function(accounts_, account, locks, lock)
      e.account_items, e.account_label, e.lock_items, e.lock_label = accounts_, account, locks, lock
    end,
    on_status = function(value)
      e.status = value
    end,
    on_selected = function()
      e.accepted = e.accepted + 1
    end,
  })
  function e.catalog(devices, scope, nonce, source)
    return e.selection:catalog(
      source or e.selection.account,
      nonce or e.selection.request_nonce,
      { ready = true, scope = scope or "scope-A", devices = devices }
    )
  end
  return e
end
local devices =
  { { id = "front", name = "Front Door", available = true }, { id = "garage", name = "Garage Door", available = true } }

T.section("One account, a dropdown of discovered locks, explicit stable choice")
local e = fixture()
e.selection:refresh()
T.eq("single available account is automatic", e.selection.account, 11)
T.eq("requests only a public catalog", e.sent[1].command, "SCHLAGE_CATALOG_REQUEST")
e.catalog(devices)
T.eq("readable available lock names", e.lock_items, { "Select a lock", "Front Door", "Garage Door" })
T.eq("never selects the first lock implicitly", e.selection.id, "")
local old_nonce = e.selection.request_nonce
e.selection:choose_lock("Front Door")
T.eq("choosing a lock detaches previous connection", e.detached, 1)
T.eq("selected cloud ID saved", e.saved.id, "front")
T.falsy("earlier catalog response ignored", e.catalog(devices, nil, old_nonce))
e.catalog(devices)
T.eq("selection request targets exact ID", e.sent[#e.sent].params.ID, "front")
T.eq("selection request is scoped to account", e.sent[#e.sent].params.SCOPE, "scope-A")
e.provider = 11
e.selection:accepted(11, { NONCE = e.selection.request_nonce, ID = "front", SCOPE = "scope-A", SUCCESS = "true" })
T.eq("acknowledgement requests fresh bound state", e.accepted, 1)
e.catalog({ { id = "front", name = "Main Entry", available = true } })
T.eq("rename updates dropdown label", e.lock_label, "Main Entry")
T.eq("rename retains stable selected ID", e.selection.id, "front")
e.catalog({ devices[2] })
T.eq("removed selection stays identified as unavailable", e.lock_label, "Unavailable selected lock")
T.eq("removal never selects a different lock", e.selection.id, "front")
e.catalog(devices)
T.eq("reappearance restores label", e.lock_label, "Front Door")

T.section("Multiple companions are independent, including within one room")
local a, b = fixture(), fixture()
a.room, b.room = 7, 7 -- room is project placement, never a selection constraint
a.selection:refresh()
b.selection:refresh()
a.catalog(devices)
b.catalog(devices)
a.selection:choose_lock("Front Door")
b.selection:choose_lock("Garage Door")
a.catalog(devices)
b.catalog(devices)
T.eq("same-room companions choose different physical locks", { a.selection.id, b.selection.id }, { "front", "garage" })
T.eq("selection does not move companions", { a.room, b.room }, { 7, 7 })

T.section("Account changes, stale replies, restart and explicit deselection")
e = fixture(nil, { [11] = "First", [22] = "Second" })
e.selection:refresh()
T.eq("multiple accounts need explicit choice", e.selection.account, nil)
e.selection:choose_account("11: First")
e.catalog(devices)
e.selection:choose_lock("Front Door")
e.catalog(devices)
local previous = e.selection.request_nonce
e.selection:choose_account("22: Second")
T.eq("account switch clears old target", e.selection.id, "")
T.falsy("old account catalog cannot repopulate dropdown", e.catalog(devices, nil, previous, 11))
e.catalog(devices, "scope-B")
e.selection:choose_lock("Garage Door")
e.catalog(devices, "scope-B")
T.falsy(
  "old selection acknowledgement cannot activate lock",
  e.selection:accepted(11, { NONCE = previous, ID = "front", SCOPE = "scope-A", SUCCESS = "true" })
)
local restarted = fixture(e.saved, e.accounts)
restarted.selection:refresh()
restarted.catalog(devices, "scope-B")
T.eq("restart restores selected account", restarted.selection.account, 22)
T.eq("restart restores selected lock", restarted.sent[#restarted.sent].params.ID, "garage")
restarted.catalog(devices, "different-account-scope")
T.eq("same controller driver with changed cloud account requires a new choice", restarted.selection.id, "")
restarted.selection:choose_lock("Front Door")
restarted.catalog(devices, "different-account-scope")
T.falsy(
  "wrong target handoff cannot activate selected companion",
  restarted.selection:accepts({ id = "garage", scope = "different-account-scope", online = true, bolt = "locked" })
)
restarted.selection:choose_lock("Select a lock")
T.eq("explicitly clearing lock persists no target", restarted.saved.id, "")
T.eq("clear choice stays offline and unbound", restarted.provider, 0)
T.falsy(
  "explicitly cleared selection rejects late old-lock handoff",
  restarted.selection:accepts({ id = "front", scope = "different-account-scope", online = true, bolt = "locked" })
)

T.section("Unavailable discovery and duplicate/special names stay usable")
e = fixture()
e.selection:refresh()
e.catalog({
  { id = "00000000-a", name = "Door, West", available = true },
  { id = "00000000-b", name = "Door, West", available = true },
  { id = "taken", name = "Assigned Elsewhere", available = false },
})
T.eq("assigned elsewhere omitted from available choices", #e.lock_items, 3)
T.neq("duplicate display names have distinct menu labels", e.lock_items[2], e.lock_items[3])
T.excludes("comma cannot split an item", e.lock_items[2], ",")
T.neq(
  "duplicate labels retain distinct identities",
  e.selection.lock_labels[e.lock_items[2]].id,
  e.selection.lock_labels[e.lock_items[3]].id
)
e.selection:catalog(11, e.selection.request_nonce, { ready = false, devices = {} })
T.eq("unavailable account clears stale choices", e.lock_items, { "Select a lock" })
T.eq("unavailable discovery is visible", e.status, "Waiting for account discovery")
T.finish()
