# Design

## Context

See [proposal.md](proposal.md) for motivation and [the capability specs](specs/) for the behavior contract. At the start of this change, the project contained OpenSpec planning files and generated Codex skills only. Implementation progress is tracked in tasks.md; controller validation is recorded in docs/hardware-validation.md.

Read-only source review on 2026-11-05 established these reference points:

| Reference | Observed behavior and intended use |
| --- | --- |
| [Finite Labs template](https://github.com/finitelabs/control4-driver-template/tree/4aabee67ddc8ac71602e6d6367b41794e831f022) | Copier-managed libraries, async HTTP, encrypted persistence, build/packaging, local C4 shim, crypto big numbers and generic SRP. |
| [ESPHome](https://github.com/finitelabs/control4-esphome/tree/5e9e04e2d3007caa0ba7a468ca86353f3d55d9cb) | `drivers/esphome_lock` implements lock proxy commands and notifications. Yale adds bounded command age, restart recovery tests, and delayed jam checks. |
| [Nuheat](https://github.com/finitelabs/control4-nuheat/tree/dabaa1ab8b67abe2af3ab0a14adb522916f5cd27) | Account/companion bindings, Add Devices, nonoverlapping polls, HTTP 429 handling, write readback, and rejection of stale reads. Its OAuth login is a different protocol. |
| [Hatch](https://github.com/finitelabs/control4-hatch/tree/1ae080ebe8ae521e7c8dd541b198ae2b3bff070f) | Native Cognito identity-pool credential exchange and MQTT over WebSockets. It does not implement Cognito user-pool SRP; retain as a future push reference. |
| [pyschlage](https://github.com/dknowles2/pyschlage/tree/6b31f8bd2cdc15d129855d667b9674ee2ce68120) | Cognito configuration, REST routes, device-type discrimination, lock state mapping, and detailed protocol notes. HA currently pins a published version; reviewed main contains newer behavior that needs fixtures and live verification. |
| [pycognito SRP](https://github.com/NabuCasa/pycognito/blob/master/pycognito/aws_srp.py), [Hubitat Schlage](https://github.com/schwark/hubitat-schlage/blob/main/schlage.groovy) | Cognito-specific SRP calculations, challenge payloads, client secret hash, timestamp format, and refresh-token preservation. These are protocol references, not drop-in Lua modules. |

No reference establishes compatibility with the user's actual controller or locks. Hardware identity and OS version are captured before controller validation; release support lists only tested combinations.

## Goals / Non-Goals

**Goals:** Keep one cloud session per configured account driver; isolate protocol code from Control4 presentation; make authentication and command outcomes testable with sanitized fixtures; keep all runtime communication on the controller.

**Non-Goals:** Reimplement Finite Labs shared infrastructure, copy unrelated ESPHome transports, require vendor-hosted authentication, or advertise deferred lock features. Functional scope is defined in the proposal.

## Decisions

### 1. Scaffold from a pinned template and adapt focused reference code

Choose a reviewed tagged template release during implementation and retain Copier's answers file. Render into a temporary staging directory, inspect the output, and copy it into this project without overwriting OpenSpec files or generated skills. Use the OSS build; give the driver its own identity, repository/update settings, and notices. Disable optional external diagnostics. Do not run the template's GitHub repository/settings automation as part of scaffolding.

Keep shared `src/lib/`, vendored modules, and shared tests template-managed. Schlage-specific code belongs under `src/schlage/`, `drivers/schlage_account/`, `drivers/schlage_lock/`, and dedicated fixtures/tests. Select `bitn crypto`; generic OAuth, ESPHome protobuf/Noise, and BLE modules are unnecessary. A wholesale ESPHome fork would carry unrelated transports; hand-building the toolchain would duplicate available infrastructure.

### 2. Native Cognito is the first implementation gate

Template maintenance on 2026-11-08 updates the original v0.9.74 pin to v0.9.80
(2da61295cab1af22b89d18a2dad36c94a4e3f00f). Keep `bitn crypto` selected and
external diagnostics, expressions, and OAuth modules disabled. The updated logger
sets raw Control4 debug switches when Ultra and Print are selected; each Schlage
driver must disable those switches after applying logger settings. Preserve
template-managed code and verify this integration through driver-level tests.
The smaller vendor bundles retain runtime crypto checks; source and packaged
Cognito/SRP tests must pass before release. This maintenance does not complete
deferred outage/recovery or daily battery hardware acceptance.

Implement a dedicated Cognito SRP adapter using the bundled big-number, SHA-256, HMAC/HKDF, and verified cryptographically secure randomness primitives. Reuse the primitives rather than calling generic `crypto.srp` unchanged: its default group generator, encoding rules, session key, and proof are designed around HomeKit conventions.

Implement `InitiateAuth(USER_SRP_AUTH)` and `RespondToAuthChallenge(PASSWORD_VERIFIER)` over asynchronous HTTPS, including Cognito's signed integer padding, pool-specific identity hash, HKDF label, canonical challenge username, client secret hash, secret block, and English UTC timestamp. Derive golden vectors independently from pinned pycognito code. Never use the Hubitat example's general-purpose Random as the entropy source.

Share a single in-flight authentication/refresh operation. Persist protected tokens with the account identity and preserve the previous refresh token when none is returned. Refresh ahead of expiry and resume by refresh after restart. A permanent refresh rejection requires explicit installer sign-in; transient failures back off. An account lifecycle generation invalidates all old callbacks and request results.

Before lock commands are implemented, verify native cryptographic acceleration, secure randomness, HTTPS/TLS trust, successful login, discovery, renewal, and restart on the target controller. Measure synchronous crypto time against a 250 ms engineering budget and confirm another driver's timer remains responsive. Missing acceleration or an exceeded budget blocks this gate for that controller; optimize the native path rather than adding an authentication server or silently running a multi-second pure-Lua calculation.

### 3. One account driver and stable lock companions

`schlage_account` owns the authenticated REST client, device registry keyed by cloud device ID, discovery bindings, availability, polling, and mutation scheduling. `schlage_lock` owns proxy presentation and sends explicit lock/unlock intents through its account binding. Use stable bindings derived from Nuheat's account/companion pattern. The installer places one companion per physical lock in any Composer room, then selects the Schlage Account and Lock from dropdowns on that companion's Properties page. A single account is chosen automatically for a new companion. Several companions may share a room. Public catalogs populate the dropdown, and explicit selection creates the connection automatically. Persistent selection is keyed by cloud account scope and device ID; changing selection cancels old pending work and rejects old handoffs. Removed devices go offline without silently deleting project devices. The account-wide Add Locks to Room workflow is replaced.

Companion messages contain a normalized public device snapshot, never raw cloud responses with CAT/SAT or tokens. Suggested modules are `cognito.lua`, `cognito_srp.lua`, `client.lua`, `device.lua`, and `commands.lua` under `src/schlage/`. This boundary permits authentication and cloud parsing to be tested independently of driver callbacks.

### 4. REST polling is the initial status transport

Use `https://api.allegion.yonomi.cloud/v1` with the Cognito access token and API key as demonstrated by pyschlage. Discover through `GET devices?archetype=lock`; read an individual device for command confirmation. For supported Wi-Fi models send `PUT devices/{id}` with only `attributes.lockState` set to 1 or 0. Keep configuration in one module, and reject unrecognized device types rather than falling through to Sense/bridge command variants.

Poll every 30 seconds by default, clamped to at least 15 seconds; permit one scheduled poll in flight. On transient failures use jittered exponential retry delays from 5 seconds to 5 minutes. Honor valid Retry-After values and use 60 seconds when a 429 supplies none. Track last successful reads and take account data offline at 120 seconds of staleness; explicit disconnected devices go offline immediately. Never interpret an HTTP error as an empty device list.

MQTT is deferred. Protocol notes report account client-ID contention with the phone app, so a future push implementation must preserve polling recovery. Hatch's WebSocket/MQTT lifecycle code can be adapted then; its identity-pool login and topic conventions cannot be copied verbatim.

### 5. Report confirmed state and bound command lifetimes

Track last confirmed state separately from pending intent and command outcome. Serialize writes per device and coalesce only unsent requests to the latest explicit intent. Resolve toggle once from fresh known state; reject ambiguous toggles. Expire unsent intents after 30 seconds and keep them in memory only.

The generic Door Lock sends TOGGLE for each tap. A fresh known reported state remains a prerequisite. While a live queued intent or an unrejected in-flight intent exists, resolve a new toggle once against that latest target, so a second tap reverses the requested action even when cloud state has not caught up. Without such an intent, resolve against the fresh reported bolt state. Ignore expired and failed targets. This desired target is never presented as the reported bolt position and is not persisted.

Serialization covers the cloud write in flight. After a successful HTTP acknowledgement, a newer explicit intent may supersede the older command's confirmation reads and dispatch immediately; acknowledgement alone never confirms either bolt state. Advance the device revision again and cancel the superseded readback/deadline. Failed or uncertain writes retain the reconciliation barrier, and cooldown/expiry/lifecycle rules still apply. This avoids holding a new user action behind a full older confirmation window. Log command receipt, dispatch, cloud acknowledgement/failure, reads and final outcome with monotonic elapsed milliseconds and allowlisted details, without device IDs or authentication payloads. Persist companion identity only when its account scope or cloud ID changes.

After dispatch, read at roughly 1, 3, 5, 7, 11, 15, and 29 seconds, stopping on confirmation or a fault. A background listing may also finish confirmation once the write callback has completed, provided the client accepted the observation from a read issued after this dispatch. Compare accepted read sequence and current device revision against the command baseline so retained pre-write data and superseded reads cannot confirm a command. Rejected writes remain rejected even if the reported target matches. Individual readbacks never overlap, and elapsed offsets are skipped after slow reads. The absolute deadline is 30 seconds from dispatch, including network and authentication time. A pending read is cancelled at that deadline. Network timeouts and 401/429 write responses do not cause automatic mutation replay; reconcile state and report failure/unconfirmed as appropriate. An already expired intent is never resumed after authentication or reconnection. Rate limits take precedence over readback cadence; when they prevent confirmation within the deadline, report unconfirmed. Advance per-device revisions when a write is dispatched, including uncertain or rejected writes, and discard reads from earlier revisions. Within a revision, use read sequence numbers to reject out-of-order responses. Apply the account lifecycle generation above. Use monotonic controller uptime for command age, cooldowns, and freshness; wall-clock UTC is for token expiry and HTTP-date conversion. Properties render timestamps in controller local time with its time-zone abbreviation; the existing LAST_SUCCESSFUL_UPDATE programming variable retains UTC.

Map Schlage states exactly as specified. Initialize the native lock proxy with `LOCK_STATUS_INITIALIZE` from the first reported snapshot after startup/reassignment/rebind. Send `LOCK_STATUS_CHANGED` only for later observed state changes, with a fixed public source and readable Last Action description. A reported online locked/unlocked position outside a matching pending Control4 action uses MANUAL=true; a matching pending target and fault/unknown use false. This is an inferred classification relative to the Control4 action, not an authoritative thumbturn, keypad, app, or person attribution. Duplicate or telemetry-only snapshots create no native movement event. Send independent `ONLINE_CHANGED` notifications through the standard lock proxy, and expose telemetry/outcome variables for programming. Online status derives independently from bolt position. Battery percentage and coarse low-battery state remain distinct. Advertise only implemented capabilities in XML; a deadbolt state does not imply door position.

### 6. Protect secrets at every boundary

Use masked credential-entry properties, immediately move entered values into encrypted persistence, and clear plaintext property values. Distinguish an intentional Sign Out action from property clearing. Never persist a command queue. Build examples, fixtures, error logs, HTTP tracing, and third-party debug switches must not reveal credentials, SRP intermediates, PINs, CAT/SAT, or identity-token headers. Add Schlage-specific redaction before any generic logging boundary; test the highest supported logging level. Verify a project export and restart for credential handling on the controller.

### 7. GitHub release delivery

Reuse lib.github-updater and lib.update-settings without changing template-managed modules. The lowest project-ID Schlage Account coordinates installed Schlage packages, installs companions before its own account package, and starts automatic checks after 60 seconds and then every six hours. Automatic Updates defaults On, with Stable the default Update Channel and Prerelease an explicit option. Settings are shared across account and companion instances and synchronized when a new instance starts. Manual Check for Updates works with automatic checking Off. Start checks while command queues are idle; preserve existing lifecycle cancellation and encrypted credentials across driver reloads. A failed check reports a persistent status and retries at the bounded interval, without exposing raw response/error data or interrupting Schlage authentication.

Use a committed VERSION in YYYYMMDDRR format: a UTC release date and two-digit increasing revision. This is an integer supported by the driver version field and newer than existing YYYYMMDD previews. Match the numeric core of each release tag to VERSION. Stable and prerelease publications both receive a new numeric revision. Keep the stock template packaging tools intact; use a project-specific version helper from Makefile.local and the tag-build workflow. Public GitHub release assets require repository publication; do not claim live automatic installation from mocks or from a local build.

### 8. Useful template integrations

Property publication starts in OnDriverLateInit, as required by DriverWorks.
OnDriverInit retains variable registration and binding restoration and cancels
old asynchronous work. Account cleanup must not publish property/variable state
while reinitialization is in progress; LateInit publishes startup presentation
and the restored session/discovery lifecycle supplies current observations.
This corrects API timing, but does not claim to fix Composer's stale project
view. File > Refresh is a documented manual alternative to investigate before
restarting Composer. Every commit requires independent review of the complete
diff before it is made.

Use template event and conditional helpers for stable Composer programming IDs, emitting observed transitions rather than initial-sync or repeated snapshots. Keep availability, reported bolt, low battery, and command outcome independent. Add local diagnostics through an allowlist plus the template redactor; never include lock IDs, account scopes, credentials, raw responses, or user-defined names. Give account and companion Composer entries independent project icons, leaving generic Door Lock Navigator icons native. Retain the existing disabled external cloud diagnostics and OSS-only licensing policy. Review remaining template options in docs/template-feature-review.md.

### 9. Daily low-battery reminders

The Schlage Account owns the Low Battery Push Notifications On/Off option (default Off), local HH:MM reminder time (default 09:00), and percentage threshold (default 20%). These apply to all supported locks discovered on that account, including locks without companion instances. Evaluate accepted public snapshots at the first fresh online observation at or after the reminder time. A Schlage low-battery flag or a supplied percentage at/below the threshold qualifies. Unknown battery data alone does not qualify. No additional Schlage requests or recurring alert timer are needed; normal account polling drives evaluation. Never alert from offline, unsupported, or more than 120-second-old observations.

Persist daily event/push markers before dispatch in encrypted account storage, keyed by account scope and physical lock ID, so reloads, repeated polls, same-day low/normal flapping, and credential changes do not repeat a daily delivery attempt. Keep event and push attempt markers independent so enabling automatic push after the daily event ran can still request one push that day. Do not replay missed days or retry an uncertain push submission automatically. Local dates, rather than fixed 24-hour timers, handle daylight-saving changes. Reject invalid reminder times visibly without sending.

Expose a stable Daily Low Battery Alert Composer event and a readable message variable on the account for optional custom programming, independently of automatic push. The automatic option reuses the existing Control4 Push Notification agent without requiring the installer to configure templates or event programming. Verify the agent's command contract from actual definitions or a reliable implementation before dispatch; the installed Chowmain Home Assistant Gateway is encrypted and establishes the desired UI behavior, not an inspectable code reference. Any driver-owned agent configuration must avoid overwriting user-owned entries. Sending to the agent is a submission attempt, not proof that a phone received it. A separately labeled test action exercises notification delivery without changing battery/lock state or consuming the daily reminder allowance. Document that configuring both automatic push and a push action on the event causes two messages.

## Risks / Trade-offs

- [Community-documented API changes] → Centralize protocol constants, pin reference revisions, keep response fixtures, and fail visibly on unsupported responses.
- [Cognito math works locally but stalls an older controller] → Complete the measured hardware authentication gate before building the rest of the integration; document the resulting minimum tested platform.
- [Cloud state may lag or reflect command acceptance] → Separate requested and confirmed state, verify reported-state semantics on hardware, and report unconfirmed when the deadline expires.
- [Template updates alter shared behavior] → Pin releases, keep Schlage code separate, and review Copier updates with regression checks.
- [Sensitive data can bypass generic redaction] → Normalize companion payloads, test serialized and nested responses plus low-level tracing, and sanitize any manually captured fixtures before committing them.
- [Hardware/cloud access unavailable] → Local fixtures prove protocol and lifecycle logic only; do not mark hardware milestones or release acceptance complete until live evidence exists.

## Migration Plan

Implement and test in a development project first. Add the account driver and one companion without changing existing HA bindings or automation. Validate manual changes, native commands, jams where safely reproducible, reboot, network outage, token renewal, and multiple locks before moving production programming. Prevent duplicate automations during the eventual cutover. Roll back by disabling/removing the new driver instances and restoring the original bridge bindings; no lock reset or re-enrollment is required.

## Open Questions

- Which exact controller model, OS version, lock model identifiers, and firmware versions will populate the initial hardware validation record?
- Companion placement is chosen in Composer; any room may contain multiple independently selected locks.

These are commissioning inputs; authentication feasibility and protocol correctness remain explicit acceptance gates rather than assumed capabilities.
