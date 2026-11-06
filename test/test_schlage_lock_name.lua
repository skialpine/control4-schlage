require("c4_shim")
local T = require("testlib")
local Name = require("schlage.lock_name")
local connections = {
  [10] = { [5010] = { [20] = "Companion", [99] = "Unrelated" } },
  [20] = { [5001] = { [21] = "Proxy" } },
  [21] = { [1] = { [30] = "Door tile", [31] = "Auto-Lock" } },
}
function C4:GetBoundConsumerDevices(id, binding)
  return (connections[id] or {})[binding]
end
local devices = {
  [20] = { deviceName = "Schlage Lock", driverFileName = "schlage_lock.c4z" },
  [21] = { deviceName = "Front Patio Lock", driverFileName = "lock.c4i" },
  [30] = { deviceName = "Front Patio Door", driverFileName = "relaysingle_doorlock_c4.c4i" },
  [31] = { deviceName = "Auto Lock Button", driverFileName = "door_autolock.c4z" },
  [99] = { deviceName = "Other device", driverFileName = "unrelated.c4z" },
}
ShimSetDevices(devices)
T.eq(
  "prefer visible Control4 Door Lock tile over Schlage name",
  Name.resolve(10, 5010, "Schlage cloud name"),
  "Front Patio Door"
)
devices[30].deviceName = "Renamed Patio"
T.eq("project renames are read when sending", Name.resolve(10, 5010, "Schlage cloud name"), "Renamed Patio")
connections[21][1][30] = nil
T.eq(
  "auto-lock button is not mistaken for visible lock",
  Name.resolve(10, 5010, "Schlage cloud name"),
  "Front Patio Lock"
)
connections[20][5001] = {}
T.eq("companion name is next fallback", Name.resolve(10, 5010, "Schlage cloud name"), "Schlage Lock")
connections[10][5010][20] = nil
T.eq(
  "lock without companion uses Schlage account name",
  Name.resolve(10, 5010, "Schlage cloud name"),
  "Schlage cloud name"
)
T.eq("missing binding does not query unrelated devices", Name.resolve(10, nil, "Cloud name"), "Cloud name")
T.finish()
