# Upstream notices

The project is distributed under AGPL-3.0; see LICENSE.

- Finite Labs Control4 driver template v0.9.74, commit
  `4aabee67ddc8ac71602e6d6367b41794e831f022`, by Finite Labs, LLC:
  <https://github.com/finitelabs/control4-driver-template>. Template-managed
  libraries, vendored bundles, tests, and tooling retain their upstream notices.

- The `vendor/drivers-common-public` files retain Control4/Snap One copyright
  notices. Other vendored modules retain the notices embedded in their sources.

- Finite Labs Control4 Nuheat (AGPL-3.0), commit
  `dabaa1ab8b67abe2af3ab0a14adb522916f5cd27`:
  <https://github.com/finitelabs/control4-nuheat>. Account/companion binding
  patterns adapted in `src/schlage/registry.lua` and `bridge.lua`. Schlage uses
  public normalized handoffs, account-scoped identity, and its own command
  reconciliation policy.

- Protocol references: pyschlage (Apache-2.0), pycognito (Apache-2.0), and
  Hubitat Schlage (MIT). Reference revisions and any copied material will be
  recorded with the native authentication implementation.

- Finite Labs Control4 ESPHome (AGPL-3.0), commit
  `5e9e04e2d3007caa0ba7a468ca86353f3d55d9cb`:
  <https://github.com/finitelabs/control4-esphome>. Standard lock proxy command,
  status notification, and XML capability patterns adapted in
  `drivers/schlage_lock`. No ESPHome transport or PIN-management code is used.

The OSS drivers use their own identity. No Finite Labs cloud diagnostics,
DriverCentral licensing client, or vendor service credentials are required.
