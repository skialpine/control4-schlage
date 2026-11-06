require("c4_shim")
local T = require("testlib")
local Diagnostics = require("schlage.diagnostics")
local report = Diagnostics.render({
  role = "lock",
  version = "2026110601",
  os_version = "3.4.3.741643-res",
  online = true,
  bolt = "locked",
  battery_percent = 87,
  low_battery = false,
  update_channel = "Prerelease",
  automatic_updates = "On",
  log_mode = "Off",
  log_level = 3,
  selected = true,
  outcome = "confirmed",
  password = "SENTINEL-password",
  id = "SENTINEL-id",
  scope = "SENTINEL-scope",
  email = "SENTINEL@example.invalid",
  session = { access_token = "SENTINEL-token" },
  CAT = "SENTINEL-CAT",
  PIN = "SENTINEL-PIN",
})
T.contains("public state is useful", report, "locked")
T.contains("version is present", report, "2026110601")
T.contains("controller release is present", report, "3.4.3")
T.excludes("identifiers, credentials and nested responses are absent", report, "SENTINEL")
report = Diagnostics.render({
  role = "SENTINEL",
  bolt = "SENTINEL",
  version = "SENTINEL",
  os_version = "SENTINEL",
  battery_percent = 0 / 0,
})
T.excludes("even named public fields are validated", report, "SENTINEL")
T.excludes("NaN does not reach JSON output", report, "NaN")
T.finish()
