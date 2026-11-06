# Proposal

## Why

The existing Home Assistant bridge adds a dependency between Control4 and Schlage Wi-Fi locks. Build an open-source DriverWorks driver that authenticates and communicates with Schlage directly from the Control4 controller, using the Finite Labs template and existing Schlage implementations as references.

## What Changes

- Introduce an account driver that owns native Cognito SRP authentication, encrypted token persistence, renewal, lock discovery, and cloud polling.
- Introduce one installer-placed companion driver per selected lock, with account/lock Properties dropdowns and unrestricted room placement (including multiple locks in one room), exposing Control4's standard lock interface with lock/unlock, confirmed state, jammed status, battery information, and connectivity.
- Use the Finite Labs template for shared libraries, build tooling, documentation, and local test support; adapt ESPHome's lock proxy and Nuheat's account/companion patterns.
- Validate Cognito calculations against pycognito and the Hubitat Schlage implementation, using pyschlage for endpoint and device-state behavior.
- Integrate the template's GitHub Releases updater with shared automatic-update/channel settings, coordinated account/companion installation, manual checks, and monotonically increasing release revisions.
- Add local allowlisted diagnostics, stable Composer programming events/conditions, and independent driver icons using the applicable template infrastructure, without enabling external telemetry or commercial licensing.
- Prove authentication on a real controller before completing lock functionality. Deliver an installable OSS driver bundle and commissioning documentation after live validation.
- Initial scope is the Encode Wi-Fi family already reachable through the Schlage Home cloud. Exact controller/OS and lock models must be recorded during commissioning; untested models are not claimed as supported.
- Defer PIN management, schedules, activity-history UI, MQTT push, Bluetooth, HomeKit, Z-Wave, and offline control to separate changes. Internet and the Schlage cloud remain runtime dependencies.

## Capabilities

### New Capabilities

- `schlage-account`: Direct cloud authentication, protected credentials, account lifecycle, discovery, and bounded polling shared by all lock companions.
- `schlage-lock-control`: Native Control4 lock presentation, command delivery and confirmation, state mapping, battery reporting, and offline/fault behavior.

### Modified Capabilities

None. This is a new project with no existing capability specifications or implementation.

## Impact

- New Lua account/client modules, account and lock driver XML/Lua, tests, documentation, and `.c4z` packaging will be introduced during implementation.
- Runtime dependencies: Control4 DriverWorks HTTPS, timers, cryptography, persistence, bindings, and Schlage/Allegion's community-documented REST API and AWS Cognito user pool. No Home Assistant, external authentication server, Python daemon, or additional hub is required at runtime.
- Development dependency: Finite Labs Copier template and its Python/Lua toolchain. Select and pin a template release at implementation time; preserve planning files while scaffolding.
- Retain upstream attribution and license notices; the template and referenced Finite Labs drivers are AGPL-3.0, pyschlage is Apache-2.0, and Hubitat Schlage is MIT.
- No existing installation is modified by this proposal. Hardware testing and cloud access are implementation acceptance gates.
