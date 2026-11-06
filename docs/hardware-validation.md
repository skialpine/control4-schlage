# Hardware validation record

Change: [native-schlage-driver](../openspec/changes/native-schlage-driver/proposal.md)

Started: 2026-11-05. Current status: v2026110606-beta.1 is installed on the
CORE1 / OS 3.4.3.741643-res test system. Native authentication, discovery,
renewal, restart recovery, lock/unlock, and live app updates for reported
external bolt changes are verified. The user has checked both installed driver
versions and both Documentation tabs. Delivery acceptance (6.3) is complete.
Rollback (6.4) was closed by explicit user acceptance. Hardware task 6.1 is now complete. The remaining task is outage/recovery
(6.2). The user now reports
successful loading and basic operation on CORE5 / OS 4.3; advanced checks on
that controller and its current exact build remain unrecorded.

The sections below retain chronological observations, including superseded
preview limitations; use the latest result for current acceptance status.

## Target installation

| Item | Recorded value | Evidence |
| --- | --- | --- |
| Initial controller model | CORE 1 | User confirmed available |
| Initial Control4 OS version | 3.4.3.741643-res | Active controller confirmed by user and Composer application log |
| Follow-up controller model | CORE 5 | User reports successful loading and basic operation, 2026-11-06 |
| Follow-up Control4 OS version | OS 4.3; previously detected 4.3.0.766029-res | User now reports working operation on OS 4.3; current exact build has not been separately rechecked |
| Controller test order | CORE 1 on OS 3, then CORE 5 on OS 4.3 | User specified order |
| Composer Pro available | Yes | User confirmed possession |
| Planned development access | Installer-managed through Composer Pro on the initial CORE 1 target; project name not recorded | User supplied Composer Pro availability and intended controller |
| Method of collecting sanitized results | Not yet recorded | To establish before live validation |
| Schlage Home account with a supported Encode-family Wi-Fi lock available | BE499WB (Encode Plus), available as the initial test lock | User supplied the Schlage Information screen in response to the test-lock request |

Record availability and access method here; enter credentials through the driver's
protected commissioning interface when it exists.

Record the selected Composer project and exact OS versions/builds before
controller validation. Keep measurements and acceptance results separate for
the two targets.

## Lock inventory

Use a local alias for each physical lock. Record cloud identifiers only in a
sanitized form sufficient to correlate discovery results with that alias.

| Local alias | Product/model | Cloud device type | Firmware | Available for testing | Evidence |
| --- | --- | --- | --- | --- | --- |
| Test lock 1 | Schlage Encode Plus / BE499WB | Awaiting authenticated discovery; do not infer the cloud suffix from the retail model | Main 5.0.1300214; touchpad 2.0.1300219; BLE 2.2.1224075; Wi-Fi 3.22.0.1 | Yes, user supplied as the test lock | User-provided Information screenshot, 2026-11-05 |

The screenshot's phone OS version is not the controller OS version. The lock's
serial number and the source image are not copied into this repository.
Hardware identity is recorded; compatibility and cloud transport remain untested.

## Native authentication gate

These checks correspond to tasks 3.1–3.3. Every result is pending until measured
on the target controller. Mock results do not satisfy this gate.

| Check | Required evidence | Result |
| --- | --- | --- |
| HTTPS/TLS trust | Successful authenticated HTTPS requests from the controller with certificate validation enabled | Native sign-in/discovery succeeded with the build configured for ssl_verify_host=true; target OS/build and trust observations still to record |
| Secure randomness | Selected cryptographically secure source and successful byte generation | Controller preflight reports available; native SRP sign-in succeeded; source name not yet recorded |
| Big-number acceleration | Verified accelerated modular exponentiation on the controller | Controller preflight reports available; native SRP sign-in succeeded |
| Synchronous crypto duration | Measured duration against the 250 ms engineering budget | User screenshot: SRP public 31 ms; SRP proof 50 ms; both below 250 ms |
| Other-driver responsiveness | Timer observations while authentication crypto runs | Requested overlapping Sign In/probe workflow: 150 callbacks in 15,001 ms; maximum gap 140 ms, extra delay 40 ms, skipped intervals 0; CORE 1 / OS 3.4.3.741643-res |
| Native sign-in and discovery | Successful controller sign-in and sanitized lock inventory matched to the Schlage app | signed_in; two distinct validated cloud-ID records returned as Front Door / Garage Door, both be499wifi / be499WB. Installer confirms both app locks are the same BE499WB model |
| Token renewal | Successful real renewal, including refresh-token preservation | Controller screenshot confirms successful refresh at 2026-11-05 22:40:09 UTC; refresh-token preservation is covered locally, and controller restart recovery is still pending |
| Restart recovery | Session restored after controller restart without credential reentry | User reports after reboot: signed_in, 2 locks found, successful renewal at 2026-11-05 22:45:46 UTC, following the requested reboot-without-sign-out procedure |
| Secret protection | Sanitized observations from log and project-export inspection | Project export passed; user-supplied Ultra / Print and Log sign-in and renewal output contains masked encrypted session writes and no plaintext credentials or tokens |
| Runtime independence | Authentication and discovery performed directly by the controller | Observed controller-native Cognito and Allegion access with the audited account package; no runtime bridge or authentication server |

For each run, record the date, controller/OS, tested build and reference revisions,
lock alias/model/firmware, procedure, measurements, outcome, and sanitized evidence.
Do not retain passwords, tokens, SRP private values, CAT/SAT, PINs, or raw account
payloads in this record.

## Gate decision and release support

Native authentication gate: **passed on CORE 1 / OS 3.4.3.741643-res**.
Tasks 3.1–3.3 are complete from the controller observations below. The CORE 5 /
OS 4.3 target remains untested. Lock control and release acceptance remain pending.
The private review-driver checklist referenced by the template CLAUDE.md was
unavailable. Following the user's clarification, implementation continues with
the public template, pinned reference drivers, and official DriverWorks
documentation as the review basis; private-checklist compliance is not claimed.

Validated controller/OS and lock/firmware combinations: **none**.
Integrated lock testing, installation/rollback rehearsal, and release acceptance
remain pending under task group 6.

## Local preparation completed

Task groups 1 and 2 are implemented. Template v0.9.74 is pinned and the account
and inactive lock skeleton package successfully as OSS. The account build includes
masked credential entry/clearing, encrypted persistence, native Cognito SRP,
renewal, restart recovery, lifecycle cancellation, safe diagnostics, and read-only
REST discovery. It has no cloud mutation or lock proxy capability.

On 2026-11-05, the local suite passed 38 Lua test files (1,585 assertions) and
45 Python tooling tests. Three synthetic Cognito vectors agree with pinned
pycognito through the real local Lua/OpenSSL backend. `make check` passes.
Local results do not satisfy any controller measurement above.

The next step is task 3.1: install `dist/oss/c4z/schlage_account.c4z` through
Composer Pro in the intended CORE 1 project. Follow the packaged commissioning
guide, generated from `drivers/schlage_account/www/documentation/index.md`.
Record the exact OS 3 build before installation; the package minimum is 3.4.1.
Repeat validation separately on CORE 5/OS 4.3 after the initial target passes.

## Composer import observation

The user reports Composer Pro 2026.10.14. A user-provided screenshot confirms
that Add or Update Driver successfully imported `schlage_account.c4z`, but the
initial build did not appear in search. This confirms local import only, not
controller installation or native authentication.

The standalone account and inactive lock skeleton were missing `<combo>true</combo>`
and `<controlmethod>ip</controlmethod>`. These declarations were added using the
working ESPHome/Nuheat account packages and DriverWorks documentation as
references. Empty proxy declarations were removed. A regression check verifies
the standalone classification. The rebuilt account package was copied to both
the requested Control4 folder and its Drivers subfolder. The user confirms that the corrected package could be added in Composer.
Controller identity/build, crypto checks, sign-in, and discovery measurements
remain pending.

## First controller crypto observation

The user-provided Properties screenshot shows Crypto Status:
`Native acceleration and secure randomness available`. This is a positive
controller preflight observation from Check Crypto. The controller model and
exact OS build for this screenshot have not yet been confirmed. Neither SRP
timing is populated, and the account remains `sign_in_required`; live sign-in,
TLS/discovery, performance, renewal, restart recovery, and the full hardware gate
remain pending.

The screenshot also exposed clipped inline help descriptions under the credential
fields. Those descriptions were replaced with tooltips. The account was rebuilt,
the packaged XML was checked for tooltips and masked entry fields, and both
OneDrive Control4 copies were updated. Visual confirmation remains pending.

## First successful native sign-in observation

The user-provided Properties screenshot shows:

- Driver Status: `signed_in`.
- Driver Version: `20261105`.
- Discovered Locks: `Device 1: be499wifi; Device 2: be499wifi`.
- Crypto Status: `Native acceleration and secure randomness available`.
- SRP Public Time: 31 ms.
- SRP Proof Time: 50 ms.
- Log Mode: Off.

This establishes successful controller-native sign-in and read-only account
listing, and both measured synchronous phases meet the engineering budget.
The screenshot does not identify the controller model/OS or correlate either
cloud entry with a particular physical lock. The second lock's retail model and
firmware are not yet recorded. No cloud identifiers or credentials were captured.
Task groups 3.1–3.3 remain incomplete pending the other specified checks.
The next non-disruptive check is the Renew Session action and successful return
to signed_in with the same discovery result.

## Active controller identified

The user confirms the active test controller is CORE 1 running OS 3.4.3.
This identifies the platform for the previously supplied successful native
sign-in/discovery screenshot: two be499wifi devices, SRP public 31 ms, SRP proof
50 ms, and positive acceleration/randomness preflight. The follow-up CORE 5/OS
4.3 target remains untested. Renewal, restart recovery, other-driver timer
responsiveness, and secret/export inspection remain pending.

## Discovery presentation refinement

At the user's request, Discovered Locks now shows only a compact count for any
account size. The explicit Discover Locks action prints one public lock entry per
line in the Lua output, including name, device type, and model when provided,
even with Log Mode Off. Automatic sign-in/renewal discovery updates the count
without dumping the list. Raw response tables, cloud IDs, and credential fields
are excluded. The updated driver lifecycle suite passes 74 assertions, including
zero, one, and six locks and secret-sentinel exclusion with Log Mode Off. The OSS
package and both OneDrive copies were rebuilt/updated; live visual confirmation
of the refinement remains pending.

## Composer layout confirmed

The latest user screenshot confirms the updated Properties layout on the CORE 1
OS 3.4.3 test installation: inline credential help boxes are gone, Discovered
Locks shows `2 locks found`, Driver Status is `signed_in`, crypto preflight is
positive, and the displayed SRP timings remain 31 ms / 50 ms. Visual confirmation
of the tooltip/count changes is complete. The screenshot alone does not prove
that Renew Session was exercised or that a restart recovered without credential
entry. Those checks and the explicit Lua discovery listing remain pending.

## Lua listing and renewal feedback

The user's Lua output screenshot confirms two public discovery entries:
Front Door and Garage Door, both type `be499wifi` and model `be499WB`.
This confirms the explicit Lua listing works on the active controller. The
initial firmware screenshot has not yet been correlated to one of those names.
The listing is now emitted in one print call to keep its heading and rows together.

The user clicked Renew Session but could not observe the brief status change.
This alone does not establish renewal success. The new read-only Last Session
Renewal property records a UTC timestamp only after successful refresh-token
renewal (including automatic renewal and restart recovery); initial sign-in does
not set it. The Credentials property acknowledges encrypted saved values with a
masked email while retaining entry-field clearing. These changes pass the full
local suite and 83 driver-lifecycle assertions; the rebuilt account and both
OneDrive copies are updated. Their live UI behavior still requires confirmation.

## Successful controller renewal confirmed

The latest user screenshot on CORE 1 / OS 3.4.3 shows Driver Status `signed_in`,
`2 locks found`, positive crypto preflight, and Last Session Renewal
`2026-11-05 22:40:09 UTC`. That timestamp is set only after successful
refresh-token renewal, so real controller token renewal is confirmed. The
Credentials indicator shows saved values with a masked account identifier;
credential entry fields remain cleared. No account identifier is copied here.

This evidence does not independently establish whether renewal was manually
triggered or occurred automatically during the driver update, whether credentials
were reentered after that update, or whether a controller reboot recovers without
reentry. Task 3.3 remains incomplete: the full controller restart and local
log/project-export secret inspection are pending. Other-driver timer
responsiveness and app/device-ID correlation are also still pending under the
remaining group 3 acceptance checks.

## CORE 1 reboot recovery confirmed

Following the request to reboot without signing out or reentering credentials,
the user supplied a screenshot explicitly labeled "after reboot". On CORE 1 /
OS 3.4.3 it shows signed_in, two locks found, saved-credentials acknowledgement,
and a successful renewal timestamp of 2026-11-05 22:45:46 UTC (later than the
22:40:09 UTC pre-reboot observation). The cleared entry fields are visible.
This confirms the reported reboot workflow restored the account and discovery
using persisted session material. The displayed 31/50 ms SRP values are the
previous sign-in measurements; renewal does not rerun SRP.

The native authentication gate remains incomplete. A fresh controller log and
project-export inspection for plaintext secrets, another driver's timer
responsiveness during native sign-in, and explicit app/cloud identity correlation
are still pending. Keep task groups 4–6 unstarted until all group 3 checks pass.

## Project export inspection

The user supplied `lock test.c4p`. Its project XML contains one Schlage account
instance, and the embedded schlage_account.c4z matches the latest local build.
The Schlage Email and Schlage Password properties are empty. The Credentials
acknowledgement contains a masked account identifier. Legacy JSON persistence is
empty. Both SchlageCredentials and SchlageSession are stored with the export's
binary type. After removing two Base64 transport layers (including line folding),
the payloads are opaque binary rather than readable account JSON or JWTs. No
plaintext installer credentials or session tokens were found in the inspected
Schlage project entry. This is consistent with the reviewed SDK encrypted writes;
it is not an independent cryptographic audit.

The findings, source/package hashes, and checks are captured in
`docs/project-export-audit.json`; no account value, source export, or decoded
payload is copied into the repository. The source export was not modified.

## Composer application log received

The pasted Composer application log confirms client 2026.10.14.802 and active
CORE 1 Director 3.4.3.741643-res. It also discovers the future CORE 5 target at
4.3.0.766029-res; this does not validate the Schlage driver on CORE 5. The log
contains Composer connection/update/broker diagnostics, not Schlage Lua driver
logging. The broker/JSON warnings are not attributed to the Schlage driver by
this evidence. Application/dealer/controller identifiers and the raw log are not
copied into this record. Live Schlage logging and another-driver timer
responsiveness remain pending, so task group 3 is not yet complete.

## User-supplied Lua discovery output

The user supplied the explicit listing of Front Door and Garage Door, each
reported as be499wifi / be499WB. The provided lines contain only the expected
public names, device types, models, and count. No credentials, tokens, raw cloud
objects, or cloud IDs appear in those lines. This confirms safe explicit
listing, but the excerpt contains no sign-in/renewal status or persistence trace
lines and does not independently confirm the selected Log Mode/Level. The live
highest-level authentication/renewal logging check remains pending.

## Controller snapshot and renewal action feedback

The user supplied a CORE 1 diagnostic snapshot. The system-version file reports
3.4.3.741643-res-r0.0. The archive contains controller/system logs, but no Schlage
account status or discovery-count diagnostic events from the required verbose
sign-in/renewal run. This is an inconclusive runtime-log audit, not a passing
secret-filtering check and not evidence that renewal failed. Sanitized metadata
and the archive hash are recorded in docs/runtime-log-audit.json; no source
snapshot or raw log entries are copied into the repository.

The user reports Renew Session produces no Lua output even at Ultra. The manual
action previously relied on optional diagnostic logging and discarded its
completion callback. It now prints a request, the selected mode/level and active
output flags, and a successful completion or safe failure category directly in
Lua, including with diagnostic logging Off. The updated driver suite passes
98 assertions, including success/failure visibility and secret-sentinel checks.
Live validation of this action feedback and verbose authentication logs remains
pending; group 3 is still incomplete.

## Renewal output and logging configuration confirmed

The user supplied the revised manual-action output: renewal requested, logging
mode Off with level 6 - Ultra and both print/log output flags false, then renewal
succeeded. This confirms the manual renewal completion path works on hardware
and explains the previously absent diagnostics: verbosity was enabled, but the
output mode was Off. It does not establish a failure of the shared logger.

The live highest-level authentication/renewal secret-filtering check still needs
Log Mode Print and Log with level 6 - Ultra, followed by explicit Sign In and
Renew Session and inspection of that Lua/controller output. No credentials or
tokens appear in the manual-action output provided so far.

## Highest-level live logging passed

The user supplied Lua output with mode Print and Log, level 6 - Ultra, and both
output flags true. It contains one successful explicit SRP sign-in and two
successful verbose renewals, each followed by discovery of two devices. All
three SchlageSession writes are shown as ***REDACTED*** with encrypted=true.
Only fixed status/operation text, safe persistence keys, public counts, and the
logging settings appear; no plaintext credentials or token values appear.
Together with the inspected export and reported reboot recovery, this completes
task 3.3. The original snapshot remains inconclusive by itself; the later live
observation is separately recorded in docs/runtime-log-audit.json.

Task 3.1 still needs a measured timer observation from another driver during SRP
sign-in. A separate read-only validation timer probe is being prepared; it has
no lock commands, bindings, or account/session access. App/model correlation is
awaiting installer confirmation under task 3.2. Do not proceed to group 4 yet.

## Timer probe ready for controller measurement

A standalone Schlage Validation Timer development package is available under
`dist/validation` and copied to the OneDrive Control4 folder and its Drivers
subfolder. It runs a 100 ms repeating timer for 15 seconds, independently of the
account driver, and retains callback count, largest gap/extra delay, skipped
intervals, elapsed time, and start/finish UTC in Properties. It has no account,
network, persistence, binding, or lock-control functionality. Its 15 local
lifecycle assertions pass. A real run overlapping native Sign In is still
required before completing task 3.1.

## Separate-driver timer measurement accepted

In response to the requested Start Probe / immediately run account Sign In
workflow, the user supplied completed probe Properties on the CORE 1 target:

- Start: 2026-11-05 23:27:55 UTC.
- Finish: 2026-11-05 23:28:10 UTC.
- Callback count: 150.
- Maximum timer gap: 140 ms (nominal interval 100 ms).
- Maximum extra delay: 40 ms.
- Skipped intervals: 0.
- Elapsed: 15,001 ms.

These measurements show the separate driver timer remained responsive in the
requested sign-in test, with no missed intervals and bounded extra delay. Together
with prior native TLS/authentication, entropy/acceleration checks and 31/50 ms SRP
measurements, task 3.1 is complete on CORE 1 / OS 3.4.3.741643-res. This result is
not a CORE 5 validation. The sign-in overlap is based on the requested user test
procedure; no separate synchronized account log for that probe window was supplied.

Task 3.2 still awaits installer confirmation that the two returned named/model
entries correspond to the intended locks in Schlage Home. The hardware gate is
not closed until that correlation is confirmed.

## Updated Schlage app information screenshot

The user supplied a fresh Schlage Information screen dated 2026-11-05, showing
model BE499WB, main firmware 5.0.1300214, touchpad 2.0.1300219, BLE 2.2.1224075,
and Wi-Fi 3.22.0.1. These match the earlier information screen. The screenshot
does not show the lock's name, so it cannot yet be assigned to Front Door or
Garage Door. It also does not establish the second lock's model/firmware. The
serial number and source image are not retained in this repository. Task 3.2
remains pending that named-lock correlation.

## App/model correlation and hardware authentication gate completed

The installer confirms that Front Door and Garage Door are the same BE499WB
model in Schlage Home. The controller lists two distinct cloud records with
those names and type be499wifi / model be499WB; the client rejects missing or
duplicate cloud IDs before publishing discovery. This ties the validated named
cloud records to the intended model/family and completes task 3.2. Full cloud
identifiers are not copied into the validation record. The firmware information
screen documents main 5.0.1300214, touchpad 2.0.1300219, BLE 2.2.1224075, and
Wi-Fi 3.22.0.1; the second unit has no separately captured firmware screen.

All group 3 hardware authentication acceptance checks are now recorded as passed
for CORE 1 / OS 3.4.3.741643-res. These results cover native authentication,
read-only discovery, protected persistence/logging, renewal/reboot recovery,
crypto timing, and separate-driver timer responsiveness. They do not validate
lock mutation, state confirmation, polling/bindings, CORE 5 compatibility, or
release readiness.

A separate process gap was identified: the template CLAUDE.md was read only
after the user raised it. It delegates driver conventions to review-driver in
finitelabs/claude-skills. That repository returned 404 through the GitHub
connector and authenticated gh API, and no local skill copy was found in the
checked skill locations. The user confirmed that the author appears not to be
sharing those skills at this time. This is recorded as an unavailable review
source, rather than a prerequisite for further implementation. Public source
review and the project's own acceptance tests remain required.

## Native lock preview: local validation, 2026-11-05

Discovery normalization, stable account-scoped bindings, installer-triggered Add
Locks with room selection, polling/backoff/staleness, and public companion
handoffs are implemented. Native proxy commands, volatile per-lock queues,
bounded state readback, and response ordering are implemented. Local validation
passed 46 Lua suites / 1,976 assertions and 46 Python tests; formatting and
project checks passed. These are synthetic tests, not new hardware evidence.

The source review uses the public pinned references and official DriverWorks
API/XML documentation. It does not claim compliance with the unavailable private
review-driver checklist. No lock command was sent to real hardware by these tests.

Task 5.4's state/variable/notification logic is locally verified, but its actual
Navigator/Composer presentation remains pending. Tasks 6.1–6.4 remain pending,
including physical readback semantics, cloud reporting latency, outage recovery,
multi-lock operation, install/rollback rehearsal, and release acceptance. CORE 5
remains untested. Native authentication validation on CORE 1 is unchanged.

## Companion dropdown commissioning refinement

The user requested a Lock dropdown on each companion's Properties page and
confirmed that rooms may contain several physical locks. The account-wide Add
Locks to Room workflow is replaced by individually placed companions, each
selecting its account and physical lock. Local validation passed 48 Lua suites / 2,016 assertions and 46 Python tests,
including two locks in one room, separate selections, duplicate prevention,
persistent identity, renames, removal/reappearance, account changes, actual
Properties handlers, and rejection of old-lock handoffs after reselection. Actual Composer/Navigator and physical lock validation remains
pending; no new live lock command has been issued by development tests.

Next commissioning procedure:

1. Update both account and lock packages in the existing CORE 1 project. Keep
   the existing project backup and bridge available.
2. Add one Schlage Lock companion for each physical lock in the desired room(s).
   Several can share the same room. On each companion's Properties page, select
   its account and then a different physical lock from the Lock dropdown.
3. Confirm the connections are created automatically and both companions show
   appropriate online, bolt, and battery information in Composer and Navigator.
4. With the Front Door open, request Lock then Unlock and compare actual bolt
   movement, Navigator position, and Command Outcome. Repeat for Garage Door.
5. Continue manual/app-change, reboot, outage/recovery, fault, secret-inspection,
   and rollback checks before release acceptance.

## Live Composer companion observations, 2026-11-05 local

The user supplied Properties screenshots for both companions in the ongoing
CORE 1 / OS 3.4.3 test context. Each shows the account and physical-lock
dropdowns, an independent selected lock, and received state/telemetry:

| Field | Garage Door | Front Door |
| --- | --- | --- |
| Driver Status | Online | Online |
| Driver Version | 20261105 | 20261105 |
| Schlage Account | 31: Schlage Account | 31: Schlage Account |
| Lock / Selection Status | Garage Door / Selected: Garage Door | Front Door / Selected: Front Door |
| Lock Model | be499WB | be499WB |
| Bolt State | unlocked | unlocked |
| Battery / Low Battery | 100% / No | 100% / No |
| Last Update | 2026-11-06 00:48:18 UTC | 2026-11-06 00:48:48 UTC |
| Command Outcome | none | none |

This confirms the actual Composer Properties presentation, separate selections,
and public state handoff. It does not yet confirm Navigator presentation,
physical lock/unlock, command readback semantics, manual/app-change detection,
room placement, or automatic wiring without manual intervention. The timestamps
alone do not establish polling cadence. Task 5.4 remains open for the remaining
presentation/behavior checks; tasks 6.1–6.4 remain open. No driver code or package
was changed for this observation.

## Navigator visibility investigation, 2026-11-05 local

The user reports that the locks cannot be listed for Navigator placement and
supplies an empty Locks & Sensors visibility pane in Composer. A read-only
GetProxyDevicesById query on one companion returned 34, so the existing instance
does return a proxy ID; the screenshot alone did not establish correct Navigator
registration.

Source review found that the lock retained combo true from its standalone
skeleton after the standard lock proxy had been introduced. Control4's official
driver terminology describes combo drivers as lacking Navigator UI; both pinned
ESPHome Lock and Nuheat companion XML omit that flag. The flag has been removed
from Schlage Lock. The account retains its valid standalone role. The earlier
metadata test incorrectly required the flag on both roles and is corrected to
distinguish them and validate the lock proxy's LOCK connection.

Build 20261106 uses the current UTC date, consistent with CI. Test an in-place
lock-driver update and Refresh Navigators before considering recreation of an
existing instance. Actual Navigator appearance and physical lock control remain
unverified; task 5.4 is still open.

### Registration evidence after the update

The user confirmed version 20261106 in Driver Information, then supplied the
following read-only output from the existing Living-room companion:

```text
Driver ID: 34
Proxy IDs: 34
Device: 34 schlage_lock.c4z Living
```

The filtered GetDevices result printed no separate proxy entries. The earlier
single return value of 34 was therefore not evidence of a separately registered
standard lock proxy. Updating the existing instance has not resolved Navigator
visibility. Retention of the original standalone registration is a working
explanation, not yet a confirmed migration diagnosis.

At the user's request, the registration was compared with other public lock
drivers:

- [ESPHome Lock](https://github.com/finitelabs/control4-esphome/blob/5e9e04e2d3007caa0ba7a468ca86353f3d55d9cb/drivers/esphome_lock/driver.xml)
  and [ESPHome Yale](https://github.com/finitelabs/control4-esphome/blob/5e9e04e2d3007caa0ba7a468ca86353f3d55d9cb/drivers/esphome_yale/driver.xml)
  declare the standard lock proxy at binding 5001, a hidden LOCK provider
  connection, and is_management_only false, with no standalone combo flag.
- [Control4-HA-Lock](https://github.com/bphillips09/Control4-HA-Lock/blob/2b05f1eb28058a75c486c321266dc20ce68d1b51/driver.xml)
  uses the same proxy and connection structure, with combo explicitly false.
- [C4-SwitchBotUltra setup](https://github.com/efic1/C4-SwitchBotUltra/blob/main/README.md)
  instead instructs installers to add a generic Door Lock driver and bind its
  relay. This is a different commissioning arrangement; it is not required by
  the directly declared proxies in the other examples.
- [Control4's public lock template](https://github.com/snap-one/drivers-template-code-public/blob/50eee83dd690ef6724e4162f7e557d03a57b9b07/proxies/lock_proxy/lock_main.lua)
  defines the same management capability name. The reference ESPHome Lua sends
  ONLINE_CHANGED and LOCK_STATUS_CHANGED through binding 5001, as Schlage does;
  it does not add its declared standard proxy through a runtime AddDevice call.

The corrected Schlage package matches the direct-proxy registration pattern.
No further package change is justified by this comparison alone. The next
controlled check is one newly added, unassigned Schlage Lock in Living, keeping
the existing companions and account. Check the new instance's proxy metadata
and Navigator visibility before moving any physical-lock selection. A fresh
instance has not yet been tested; Navigator and physical control remain pending.

### Fresh instance and generic Door Lock finding

The user reported that a fresh Schlage Lock, including reassignment of one
physical lock to it, still did not appear in Navigator. A newly saved project
export confirms the following public registration and binding metadata:

- Older Schlage companions 34 and 35 have no separate proxy subitems.
- New Schlage protocol 36 has standard lock proxy 37 (`lock.c4i`) as a subitem.
- Protocol 36 binding 5001 is connected to proxy 37 binding 5001 using LOCK.
- The account is connected to protocol 36 at its Schlage input, binding 5002.
- All these items are in Living. The proxy's stored is_management_only value
  is False. The room's OrderedContactRelayList is empty.
- The standard proxy declares a Lock State relay output at binding 1.

The user then identified the missing commissioning step: add a generic Door
Lock and connect the Schlage lock to it. This agrees with the separate generic
Door Lock setup documented by C4-SwitchBotUltra. The earlier conclusion that a
correctly instantiated standard proxy would itself appear in Locks & Sensors
was incomplete. The installer documentation now includes the generic Door Lock
and the relay connection, distinct from automatic account/physical-lock binding.

A proposed LOCK_STATUS_INITIALIZE change was set aside before testing or
delivery once the user identified this setup step. No new Lua behavior was
installed for this finding. Generic-device appearance and successful physical
commands/state feedback have not yet been separately captured, so task 5.4 and
the hardware acceptance tasks remain open. The earlier fresh-instance test is
no longer pending; further repeated re-add attempts are not the next step.

## Basic native commands and latency investigation

After adding and binding a generic Door Lock, the user reported that Lock and
Unlock work and match the physical bolt. In the ongoing CORE 1 / OS 3.4.3
context, the bolt itself takes several seconds to move and Command Outcome
remains pending for about ten seconds. Immediate opposite changes are not
responsive. The exact tested door was not specified; this does not establish
both-lock operation, fault behavior, manual/app-change detection, or recovery.

The original scheduler serialized the entire confirmation window. The revised
preview serializes cloud writes and permits a newer explicit intent to cancel
older confirmation reads after a successful write acknowledgement. Failed or
uncertain writes retain the barrier. The new command still requires fresh
reported state for confirmation, with revision checks rejecting old reads.
Safe timing logs now distinguish receipt, dispatch, cloud response, readback,
and completion. They use command sequence/action and elapsed milliseconds,
without cloud IDs or raw request/response data. The supplied trace showed
repeated saves of the same public identity; unchanged identities are no longer
persisted on every state/outcome snapshot. No claim is made that these writes
caused the measured delay.

The new scheduling and persistence behavior requires another live check;
existing latency observations describe the previous preview. Keep task 5.4
and integrated acceptance tasks open while rapid-command behavior and the
remaining scenarios are verified.

### Generic Door Lock toggle timing

The user supplied companion logs showing TOGGLE on repeated taps. The matching
account log from the command timing preview shows command 4 resolved as Lock,
dispatched at 5 ms, and acknowledged at 130 ms. Readback still reported unlocked
at 1,111 and 3,114 ms. A second tap about three seconds later resolved command 5
as Lock again; it dispatched at 8 ms and was acknowledged at 140 ms. Its reads
reported unlocked at 1,167 ms and locked at 3,120 ms, confirming at 3,121 ms.
The earlier command's tracking was superseded at 3,147 ms. Thus the new queue
did transmit the second action promptly, but both toggles chose the same target
from cloud state that had not yet changed. No raw cloud identifiers or account
scope values from the supplied trace are retained here.

The next preview resolves repeated toggles against the latest live queued or
unrejected in-flight target, while requiring fresh known reported bolt state.
Failed or expired targets do not become the toggle baseline; desired targets
remain separate from physical-state reporting. Regression scenarios cover
double/triple taps, authentication delay, both initial bolt states, and rejection
of unknown state. The revised toggle behavior still needs live validation.

## Template integrations and updater bootstrap

Following the user's request to include appropriate template features, added
the GitHub updater, shared update settings, local allowlisted diagnostics,
Composer events/conditions, and independent account/lock icons. External
telemetry remains disabled. Initial synchronization, repeat snapshots, and
reassignment do not create bolt movement events; stable programming IDs are
restored after reload. The template libraries remain unmodified.

Bootstrap version 2026110601 is delivered locally for one-time Composer
installation. Published prerelease v2026110602-beta.1 is the intended newer
update target. A project-specific wrapper preserves companion-before-account
ordering even without C4:GetDriverFileName. Local tests exercise the actual
template TCP installer with held replies in that fallback path, in addition to
shared settings, channel selection, timers, failures, redaction, and events.
These tests do not establish that Director on the user's controller accepts
the update command; use docs/updater-commissioning.md for that check. Existing
hardware gates and CORE 5 validation remain open.

### Published updater source

Published https://github.com/skialpine/control4-schlage/releases/tag/v2026110602-beta.1
from the successful GitHub CI run 42180456907 at tagged commit
9e3aab56762e4cd2e46287b884b88fbe512c5264. The initial combined branch/tag push
started the main Build run but no tag Build/Release run; the first release was
therefore published from that successful CI artifact at the exact tagged SHA.
Both packages were verified as version 2026110602. Unauthenticated public API
and asset downloads work, and downloaded bytes match the CI artifacts. The
template updater, using the actual public release metadata, identifies both
assets as newer than bootstrap 2026110601 on Prerelease and excludes the beta
from Stable. No controller update was performed by development tools.

At the user's request the published 2026110602 files, bundle, and PDFs were
copied to the OneDrive Control4 folder, with both driver files also in Drivers.
Bootstrap-2026110601 holds the optional initial-upgrade test packages. Automatic
installation, preserved credentials/selections on that installation, and new
Composer programming controls still need live checks. OpenSpec progress is
27/32 tasks complete; the five remaining tasks are the existing hardware and
integrated acceptance work.

## Follow-up confirmation timing preview (2026-11-06)

The user supplied another CORE1 timing trace. Lock dispatched in 5 ms and was
accepted in 148 ms; reads at 1.117 and 3.151 seconds still reported unlocked,
then locked at 7.120 seconds. Unlock dispatched in 6 ms and was accepted in
183 ms; reads at 1.117 and 3.113 seconds still reported locked, then unlocked
at 7.120 seconds, with confirmation at 7.121 seconds. Both completed. Requests
were about ten seconds apart, so this does not validate rapid opposite taps.
The actual motor completion time was not measured. Ultra binding/persistence
read traces do not establish a driver bottleneck.

Version 2026110603 adds checks at five and eleven seconds and allows a fresh
client-accepted background listing to complete confirmation after the write
callback. Accepted read sequences and device revisions exclude pre-write and
superseded data. Local regressions cover rejected/uncertain writes, jams,
deadlines, cancellation, slow reads, and no mutation replay. Live confirmation
timing and rapid-tap acceptance for this preview remain pending.

The follow-up preview was published automatically by the tag-triggered Release
workflow as v2026110603-beta.1 from source commit
a410c93f016e23a7646510775c3a1aa958ac7e71. Its tag Build run 42183734826
passed formatting, all 51 Lua suites (2,136 assertions), 51 Python tests, build,
and packaging verification; Release run 42183734933 passed. Public unauthenticated
account/companion downloads match the tag CI artifacts byte for byte. Published
packages, the bundle, and PDFs were copied with checksum verification to the
OneDrive Control4 folder, with both packages also in Drivers. Prior packages
were backed up. Bundled account lifecycle, companion selection, command
scheduling, and real-client revision regressions also pass locally with source
imports excluded. The user's earlier Up to date output verifies a release
check on the controller, not download/reload installation. Live upgrade to
2026110603, confirmation timing, and rapid opposite taps remain pending.

## Automatic update and local Properties timestamps (2026-11-06)

The user reported Driver Version 2026110603 and confirmed it had automatically
updated overnight. Subsequent account logs show a successful release check
(Up to date for that then-current release) and discovery of two locks. This
establishes live automatic installation of 2026110603; it does not by itself
validate every retained selection, generic Door Lock binding, or command.

Version 2026110604 displays Last Session Renewal, Last Update Check, and Last
Update using controller local time with its time-zone abbreviation. Cognito
authentication, HTTP-date handling, epoch timestamps, and the documented
LAST_SUCCESSFUL_UPDATE programming variable retain their existing time basis.
The full local suite passes with TZ=America/Denver, including the existing
renewal-display assertion and UTC authentication vectors. Display acceptance on
the actual controller remains pending after installation.

Tag Build 42245457978 and Release 42245458145 passed for
v2026110604-beta.1 (source 2a640c8404f081437e6ff4fbfce5e2e8a044b75f).
Unauthenticated public package downloads match tag CI artifacts. Both packages
were copied to the OneDrive Control4 root and Drivers folders, along with the
updated root bundle and PDFs; checksum checks passed and prior files were
backed up. Actual local-time formatting on the controller remains to be checked.

## Navigator live-state notification preview (2026-11-06)

The user reported that the app tile did not update until tapped again or
reopened, while Composer Bolt State followed the physical lock correctly. A
Composer native lock status screenshot showed the correct Unlocked state but
a blank Last Action Description. This isolates the reported discrepancy to
presentation beyond the accepted Schlage state; it does not identify the exact
Director/app failure by itself.

Review of the official Control4 lock SDK sample at commit
50eee83dd690ef6724e4162f7e557d03a57b9b07 found a distinct initial-status
notification and change messages containing description/source/manual fields.
The prior adapter sent only LOCK_STATUS_CHANGED with LOCK_STATUS on every
snapshot, omitted initialization, and supplied no action description. Preview
2026110605 aligns initialization, change-only notifications, and public metadata
with that sample. Tests cover first sync, later lock/unlock, duplicates,
telemetry, offline state, fault/unknown, native rebind, reload, and reassignment.
Live app-tile refresh and Last Action Description remain acceptance checks;
the local shim cannot prove Director or mobile-app subscriptions. Task 5.4
remains open until those presentation checks and its remaining cases pass.

Tag Build 42248292156 and Release 42248292099 passed for
v2026110605-beta.1 (source 345287e35d0fd6c3402f6dd8647b4e2f13e156ca).
All 51 Lua suites (2,153 assertions) and 51 Python tests passed. The companion
notification/selection test also passed against bundled code with source
imports excluded (55 assertions). Public unauthenticated package downloads
match tag CI artifacts. Both packages were copied to OneDrive Control4 root
and Drivers, with the updated root bundle and PDFs; checksum checks passed
and prior files were backed up. After updating, leave the tile open, request a
change or use the thumbturn, allow cloud reporting/polling, and compare native
Composer Last Action and the tile without a second tap or navigation. The live
result remains pending; OpenSpec progress remains 27/32 tasks complete.

## Live Navigator notification result (2026-11-06)

After the 2026110605 notification preview, the user confirmed that app lock
status now changes. The companion log shows three reported transitions with
matching programming movement and confirmed events:

| Request (controller local) | Reported state / confirmed | Approximate delay |
| --- | --- | --- |
| 09:04:34 | 09:04:41 unlocked | 7 seconds |
| 09:04:43 | 09:04:48 locked | 5 seconds |
| 09:04:51 | 09:04:56 unlocked | 5 seconds |

Each reported transition sent LOCK_STATUS_CHANGED. The later account log
continues to discover two devices and contains no error in the supplied
excerpt. These durations measure request to reported confirmation with
whole-second log precision, not motor travel or HTTP latency. The requests
followed completion of the previous request, so rapid opposite actions during
a pending move remain unverified. The exact physical lock was not identified
in the companion excerpt. The Last Action Description display and local-time
Properties formatting were not separately confirmed by this report.

Task 5.4 is complete: the native adapter/state/telemetry/capability fixtures
pass, Composer follows physical bolt state, and live app-state notification
behavior is now confirmed on the CORE1 OS 3.4.3 test setup. Progress is 28/32.
The four integrated hardware/commissioning tasks remain open, including manual
thumbturn/Schlage-app changes, multiple-lock commands, fault/outage recovery,
CORE5 coverage, and rollback rehearsal. No additional runtime change or release
was made for this validation record.

## External-change presentation failure (2026-11-06)

The next outside-Control4 change updated Composer but did not update the app.
The earlier success established command-driven app updates only. Task 5.4 is
reopened and progress returns to 27/32; the full app fix is not verified. The
external-change companion log and specific method of changing the lock are
needed to distinguish a missed native notification, initialization reset, and
a generic Door Lock/proxy state-propagation issue. No runtime cause is inferred
from the Composer result alone.

The user then confirmed the outside change was a physical thumbturn. Composer
noticed it in about 20 seconds, consistent with the 30-second poll cadence.
The companion log fired Unlocked and emitted LOCK_STATUS_CHANGED at that
observation, but the app stayed stale until reopened. Version 2026110605
therefore sends a native change for the outside observation; it is not simply
a missed account snapshot or a repeated initializer. Its MANUAL flag is always
false. A direct status-only MANUAL=true test was requested before publishing
the next candidate.

A local 2026110606 draft sets MANUAL=true for online locked/unlocked changes
outside a matching pending Control4 action, retaining false for the pending
target and fault/unknown states. This is a proxy classification relative to a
pending action, not evidence of the actual physical actor. Local regression
tests cover matching targets, later outside changes despite sticky confirmed
outcomes, no pending action, opposite observations, and expired outcomes.
The direct controller flag test and complete outside-change app validation
remain pending. No 2026110606 release has been published at this point.

## Recovery after a direct native status notification (2026-11-06)

The user reported that app updates started working and confirmed executing the
requested status-only LOCK_STATUS_CHANGED notification with MANUAL=true first.
No driver release or controller installation occurred during this experiment;
the running log format is still the 2026110605 format. The direct notification
reported the already observed unlocked position and issued no lock mutation.
It may have resynchronized native proxy/relay/app state; the sequence does not
establish the specific Director/app mechanism or prove that every outside
change needs MANUAL=true.

The later log includes outside unlock observations at controller-local
09:40:48, 09:41:49, and 09:42:19 without nearby received commands or Command
Confirmed events, alongside command-driven confirmations at approximately
8, 7, 5, and 5 seconds. The user reports app updates now work. External-change
stability after driver reload/reconnect remains unverified, so task 5.4 stays
open and overall progress stays 27/32.

The unpublished 2026110606 draft was withdrawn from the working source and
saved separately as a local patch. VERSION and runtime source remain at the
published 2026110605 baseline. No candidate package was copied over OneDrive
or published. Retain the current release until repeat external-state testing
and reload behavior establish whether a runtime change is needed.

## Restart reproduces the outside-change app failure (2026-11-06)

After the requested restart test, Composer updated but the app did not. The
companion logged Locked and LOCK_STATUS_CHANGED at controller-local 09:54:32,
with no accompanying Control4 command in the supplied excerpt. Together with
the earlier recovery after a direct MANUAL=true notification, this supplies
repeatable evidence for the external native-notification path. The precise
Director/relay mechanism is still inferred, not observed internally.

The 2026110606 external-change candidate was restored for delivery. It sets
MANUAL=true for reported online locked/unlocked changes outside a matching
pending Control4 action, and false for the matching pending target, fault, and
unknown. Initialization still uses LOCK_STATUS_INITIALIZE without a manual
movement flag. This proxy classification does not identify a person, keypad,
or physical cause from REST. The shipped behavior must be retested after
installation and restart without any one-off Lua notification. Task 5.4
remains open; progress remains 27/32.

The user also confirmed that closing/reopening the lock view immediately
shows the correct app state. This supports stale live presentation while the
reported state is available, rather than a missing Schlage read. It does not
by itself identify the internal mobile-app/Director notification mechanism.

Tag Build 42257223642 and Release 42257223728 passed for
v2026110606-beta.1 (source c65336a4edfb66067a8498ed8f95805e7d4dda96).
All 51 Lua suites (2,161 assertions) and 51 Python tests passed. The bundled
companion test passed 63 assertions with source imports excluded. Public
unauthenticated account/lock downloads match tag CI artifacts. Both packages
were copied with byte verification to OneDrive Control4 root and Drivers, plus
the updated root bundle and PDFs; previous files were backed up. Version
2026110606 is now available through the Prerelease updater. After installation
and test-controller restart, repeat physical-turn changes while keeping the
app tile visible, before running any one-off Lua notification. Expected
external transitions log LOCK_STATUS_CHANGED with manual=true. Live restart
acceptance remains pending, and no remaining hardware task is marked complete.

## External-change fix verified on hardware (2026-11-06)

Following the requested 2026110606 install/restart/manual-turn test, the user
confirmed correct app updates and supplied both observed transitions:

| Controller-local observation | Reported bolt | Native notification |
| --- | --- | --- |
| 10:04:36 | unlocked | LOCK_STATUS_CHANGED; manual=true |
| 10:05:07 | locked | LOCK_STATUS_CHANGED; manual=true |

Both also fired the matching companion programming movement event. No received
Control4 command or command-confirmed event appears in this excerpt, consistent
with the outside-change test. These are observation times, not measurements of
physical-turn-to-cloud latency. The new log format establishes that the
2026110606 companion notification path is running. The live result is
user-confirmed after the requested restart test; no independent boot trace or
separate account/companion version-field capture was supplied.

Task 5.4 is complete based on the existing state/telemetry/capability fixtures,
Composer state verification, command-driven app checks, and now both outside
locked/unlocked app changes. Progress is 28/32. The remaining integrated tasks
cover broader manual/app and multi-lock scenarios, faults/outage/recovery,
CORE5 validation, complete commissioning, and rollback. No new runtime change
or release is needed for this result; retain v2026110606-beta.1.

## Delivery acceptance and rollback preparation (2026-11-06)

The user explicitly verified that both installed drivers show 2026110606 and
both Composer Documentation tabs open and read correctly. Local audit confirms
that account/lock packages in the OneDrive Control4 root and Drivers folders
match the published tag CI artifacts, have version 2026110606, and include the
generated HTML documentation and licenses. Delivered PDFs and the bundle
also match tag CI artifacts. Tag Build 42257223642 passed the 51 Lua suites
(2,161 assertions), 51 Python tests, formatting, build, and packaging checks.
Published documentation identifies CORE1 / OS 3.4.3 and the tested BE499WB
family, identifies captured firmware without asserting a second independent
firmware capture, and leaves CORE5 / OS 4.3 untested. Task 6.3 is complete;
progress is 29/32. This does not mark broader fault/outage or CORE5 acceptance
complete.

The user confirmed the original Home Assistant lock integration remains
available and working, and accepted the rollback rehearsal. No actual binding
switch/command/feedback/restoration result has yet been reported, so task 6.4
is still open. The existing saved project on disk is from 2026-11-05 18:27
Mac local file timestamp and predates the final Navigator bindings.
Request a fresh pre-rehearsal project save before recording the current native
and HA relay providers and temporarily switching one test lock. Keep drivers
installed and retain the current project; the rehearsal requires no lock reset
or account re-enrollment.

## Rollback task accepted by user (2026-11-06)

After confirming the HA integration is available and working, the user
explicitly requested marking rollback done and moving to the next task. Task
6.4 is closed by user acceptance. No fresh backup, binding-switch, HA command
feedback, or native restoration result was supplied, so those actions are not
claimed as independently rehearsed. Progress is 30/32. Remaining tasks are
6.1 broader hardware coverage and 6.2 outage/fault/recovery validation.

## CORE5 basic operation reported (2026-11-06)

The user reports loading the driver on CORE5 with OS 4.3 and that it works
fine. This establishes user-reported basic operation on the second target.
The earlier discovered build was 4.3.0.766029-res; the current exact OS build
and installed driver revision were not separately supplied in this report.
Do not infer completed multi-lock isolation, fault, outage/recovery, or timer
measurements from this general success report. Task 6.1 remains open for its
remaining explicit cases, and task 6.2 remains open. Progress stays 30/32.

The published v2026110606 documentation predates this CORE5 observation and
therefore describes that target as untested at publication. This validation
record records the newer result; revise the packaged support summary on the
next versioned release rather than replacing assets of the existing release.

## CORE5 two-lock routing passed (2026-11-06)

The user replied “both pass” to the explicit CORE5 / OS 4.3 routing check:
Front Door Lock/Unlock moved the correct physical bolt and app tile while
Garage Door stayed unchanged; Garage Door Lock/Unlock likewise left Front Door
unchanged. This verifies independent native command routing and app feedback
for both available BE499WB locks on the second controller. Task 6.1 remains
open for its remaining cases, including a separately reported Schlage-app
external-change test and current battery comparison. Fault mapping already has
local documented fixture coverage, which is distinct from a physical jam.
Progress remains 30/32; outage/recovery task 6.2 is also still open.

## Hardware behavior acceptance completed (2026-11-06)

The user replied “yes for all” to two explicit checks on the tested lock setup:
Schlage Home Lock/Unlock for each door updates its visible Control4 tile, and
each Composer Battery percentage matches Schlage Home. Exact current battery
percentages were not supplied, so no numerical values are invented. Together
with the earlier CORE5 independent Front Door/Garage Door command routing and
CORE1 physical-turn/native app checks, this completes the live behavior cases
of task 6.1.

The task permits a documented fault fixture instead of physically forcing a
jam. Use the existing passing fixtures: test_schlage_device.lua maps raw
lockState 2 and 4 to jammed with a separate fault flag;
test_schlage_commands.lua stops jammed readback with outcome fault; and
test_schlage_lock_driver.lua maps jammed to native LOCK_STATUS_CHANGED=fault,
sets JAMMED=1, and does not label it as an external locked/unlocked movement.
These were included in the release's passing 51 Lua suites. No physical jam or
live mobile fault display is claimed.

Tested hardware is CORE1 / OS 3.4.3.741643-res and user-reported CORE5 / OS 4.3
(current exact build not separately reconfirmed), with two BE499WB Encode Plus
locks, discovered as be499wifi. Firmware captured from one lock is main
5.0.1300214, touchpad 2.0.1300219, BLE 2.2.1224075, and Wi-Fi 3.22.0.1. The
second lock's matching model is user-confirmed; a separate complete firmware
capture remains unavailable. This does not extend compatibility to other
Encode models or firmware.

Task 6.1 is complete; progress is 31/32. Task 6.2 remains for live outage,
stale/offline rejection, recovery and no-delayed-unlock checks, with restart
and local rejection/expiry fixtures already available as supporting evidence.


## 2026-11-06: account-wide daily battery notifications (2026110607)

The user requested automatic daily low-battery push notifications, clarified
that the On/Off option must live on Schlage Account and apply to all its locks,
and requested the visible Control4 lock name in the message. A separate daily
Composer event remains available for custom automation.

The CORE5's native Push Notification agent returned its template list through
`C4:SendUIRequest(agentId, "GET_TEMPLATE_LIST", {})`. A user-saved project
containing a temporary notification action confirmed `SEND_NOTIFICATION` with
`TEMPLATE_ID`. That existing notification was a command-format reference only;
the implementation does not use or modify it. The user can remove that temporary
programming action. No private project export or existing notification text is
committed.

Native template add/modify fields were reviewed against openComposer source at
40ee90c20cb24ec57ce46a5389cba6daa13dbd56 (`crates/c4/src/agent_ops.rs` and
`agents.rs`). The driver creates its own separate entry for each account/lock,
reads the resulting message back before submitting it, and cancels queued work
on Off, lifecycle changes, stale data or battery recovery. Local tests verify
that unrelated notification entries remain unchanged and that two lock messages
cannot overwrite each other. Native template creation/modification and phone
delivery have **not yet been exercised with this driver on a controller**.

The option defaults Off. Account-wide defaults are 09:00 controller local time
and 20 percent; Schlage's independent low flag also qualifies. Only fresh,
online supported observations qualify. Daily event and automatic push markers
are stored encrypted by physical identity, separately, before dispatch. Reloads,
repeated polls, normal/low flapping and Off/On cannot repeat an attempt on the
same local date; missed days are not replayed. Notifications use a bound generic
Door Lock's Control4 name, with native proxy, companion and Schlage-name fallbacks.
A labeled Test Battery Alert action checks event/push wiring without changing
lock or battery telemetry or consuming the daily allowance.

All 54 Lua suites (2,312 assertions), 51 Python tests, formatting/project checks,
and strict OpenSpec validation passed. Package tests with source imports excluded
passed for the account (110 assertions), daily alert policy (106), native push
adapter (29), visible name resolver (6), and companion regression (63). Both
versioned packages and both documentation PDFs built successfully. Live push
acceptance and the pre-existing task 6.2 outage/recovery check remain pending.

Tag Build 42276611584 and Release 42276611283 passed for
v2026110607-beta.1, source 6c12d1b651aa0da9ea5e82786563f3a4fdb28fe9.
The tag runner had a lengthy system-package download delay; tests, formatting,
build and package/PDF verification subsequently succeeded. Both public
unauthenticated `.c4z` downloads match the tag CI artifacts. Packaged runtime
scripts also match the locally tested scripts. Both packages were delivered to
OneDrive Control4 root and Drivers, with the CI bundle and both documentation
PDFs in the root; all seven destination files passed checksum verification.
Earlier files were backed up with a suffix that Composer does not load as a
driver. The user can now run Check for Updates with Update Channel Prerelease,
confirm 2026110607, enable Low Battery Push Notifications on the account, and
run Test Battery Alert. No phone-delivery result has yet been supplied.


### Composer definition refresh and successful live TEST notification

After the GitHub update, the CORE5 account reported version 2026110607 and
`GetDriverConfigInfo("config")` contained the new battery option, but Composer
still displayed the earlier property layout. Reopening Composer did not resolve
it. The active package in the synced Drivers directory matched the published
CI package exactly and included every new battery property. The user reloaded
the driver in Composer and reported that it worked. The user explicitly asked
that future deliveries no longer write packages into the Drivers directory.
`AGENTS.md` and the commissioning guide now require root-folder delivery only,
leaving Composer to import or synchronize its local database. Existing files
were not removed as part of this workflow change.

The user then supplied a Control4 app notification screenshot from the TEST
action. Its subject and body were labeled TEST, the body used the visible
Control4 generic Door Lock name, and it included the supplied 100% battery
reading. This confirms live driver-owned notification setup and test push
delivery on CORE5. No screenshot or private project data is committed. It does
not establish a real low-battery daily reminder, next-day suppression on hardware,
or native template modification after a changed message; those policy/lifecycle
cases remain locally tested rather than independently observed on the controller.
