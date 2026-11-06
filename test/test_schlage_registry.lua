local T = require("testlib")
local Registry = require("schlage.registry")
local stored, publications, next_binding = {}, {}, 5012
local bindings = {}
function bindings:getDynamicBindings(ns)
  return stored[ns] or {}
end
function bindings:getDynamicBinding(ns, id)
  return (stored[ns] or {})[id]
end
function bindings:getOrAddDynamicBinding(ns, id, _, _, name, class)
  stored[ns] = stored[ns] or {}
  local binding = stored[ns][id]
  if not binding then
    binding = { bindingId = next_binding, class = class }
    next_binding = next_binding + 1
    stored[ns][id] = binding
  end
  binding.name = name
  return binding
end
local registry = Registry.new({
  bindings = bindings,
  publish = function(binding, device)
    publications[binding] = device or false
  end,
})
local function device(id, name, supported)
  return { id = id, name = name or id, supported = supported ~= false }
end

T.section("Stable identity through rename, removal, and account changes")
registry:reconcile(
  "account-A",
  { a = device("a", "Front"), b = device("b", "Garage"), u = device("u", "Unknown", false) }
)
local a = registry:binding("a").bindingId
T.eq("unsupported gets no binding", registry:binding("u"), nil)
registry:reconcile("account-A", { a = device("a", "Renamed"), b = device("b") })
T.eq("rename retains ID", registry:binding("a").bindingId, a)
registry:reconcile("account-A", { b = device("b") })
T.eq("removed goes offline", publications[a], false)
T.eq("removed connection retained", registry:binding("a").bindingId, a)
registry:reconcile("account-A", { a = device("a") })
T.eq("reappearance reuses identity", registry:binding("a").bindingId, a)
registry:reconcile("account-B", { a = device("a") })
T.neq("same cloud ID across accounts stays isolated", registry:binding("a").bindingId, a)
T.eq("previous account taken offline", publications[a], false)
registry:reconcile("account-A", { a = device("a") })
T.eq("return to original account retains mapping", registry:binding("a").bindingId, a)
registry:invalidate()
T.falsy("invalidated registry cannot route commands", registry.listed)
T.finish()
