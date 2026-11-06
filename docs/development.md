# Local development

The project is scaffolded from Finite Labs template v0.9.74, commit
`4aabee67ddc8ac71602e6d6367b41794e831f022`, using Copier 9.11.3 with
`vendor_modules="bitn crypto"`, OSS documentation, and cloud diagnostics off.
The selected GitHub owner is `skialpine`, verified from the local GitHub login.
No repository has been created or published.

`scaffold-inventory.json` records hashes before and after integration: all 16
OpenSpec and generated skill files were preserved byte-for-byte. Subsequent task
tracking edits are intentional. Shared `src/lib`, `vendor`, and shared tests
remain template-managed. `Makefile.local` limits packaging to OSS.

## Toolchain

On macOS, install Python 3, LuaJIT, StyLua 2.6.0, OpenSSL, SWIG, and Pango:

```sh
brew install luajit stylua openssl@3 swig pango luarocks
luarocks --lua-version=5.1 --lua-dir=/opt/homebrew/opt/luajit --tree=.lua install openssl 0.10.0-0 OPENSSL_DIR=/opt/homebrew/opt/openssl@3
make init
make test
make check
make build
```

The initial build used Homebrew Python 3.15, LuaJIT 2.1.1793383622,
StyLua 2.6.0, SWIG 4.5.1, OpenSSL 3.5.9, and Pango 1.58.2.
`toolchain-snapshot.txt` captures the Python packages used for that build.
To recreate those packages, install that file into a virtual environment with
Python 3.15 before running `make init`.
The driverpackager revision used was
`465ecc1cf73a85a4fdaf62fb688e9aed83e6d530`. The template's `make init`
clones the packager when absent; check out that revision to reproduce this run.

The default build produces:

- `dist/oss/c4z/schlage_account.c4z`
- `dist/oss/c4z/schlage_lock.c4z`
- Documentation PDFs under `dist/oss/docs`
- `dist/oss/control4-schlage.zip`

These are development builds. The lock skeleton exposes no lock commands.
A successful local build does not establish controller or lock compatibility.
The initial controller minimum is 3.4.1, selected for native OpenSSL availability;
actual support is subject to the measurements in `hardware-validation.md`.

## Verification

The initial template Lua suites and Python tooling tests passed. `make check`
and the complete OSS `make build` passed. Both packages were opened and their
project identity and absence of licensing/diagnostics imports checked.

`make verify` includes a clean Git working-tree requirement intended for CI;
this workspace initially has no Git repository, so that check cannot establish
local change cleanliness. Package checks can be run independently:

```sh
.venv/bin/python3 tools/package.py check-pdfs oss
.venv/bin/python3 tools/package.py check-encrypted oss
```

Keep real credentials in Composer's protected entry interface. Fixtures under
`test/fixtures/schlage` contain synthetic data only. Do not add the source
hardware screenshot, serial number, project exports, or raw cloud responses.

## Native authentication implementation

`src/schlage` contains the Cognito protocol adapter, account lifecycle,
read-only discovery, and a protected transport/diagnostic boundary. The account
uses the template's encrypted persistence and shared asynchronous URL module.
The Schlage transport serializes Cognito requests before dispatch so the URL
module preserves the required AWS content type, and uses strict JSON array/object
identity to distinguish an empty account from a malformed response.

The three synthetic golden vectors in
`test/fixtures/schlage/cognito-vectors.json` were derived by running the arithmetic
and challenge functions from pinned pycognito source, using synthetic credentials
and deterministic private inputs. Run `python3 tools/schlage_vectors.py` to
regenerate them from the pinned URL. Ordinary tests require no network. The real
Lua/OpenSSL backend is a development dependency in `.lua/`, excluded from packages.
The adapter refuses unavailable acceleration or entropy and calls the verified
native modular-exponentiation primitive without a portable fallback.

Schlage tests cover independent SRP values, asynchronous protocol errors,
concurrent renewal, expiry/backoff, restart recovery, lifecycle invalidation,
protected entry and persistence, discovery parsing, TLS/request options, and
sentinel filtering at Ultra in both print and Control4 logs. Those tests use no
real account or controller. No hardware gate has passed.

The template's generated CONTRIBUTING links assumed the project owner also owned
the template repository. Those two links are corrected to Finite Labs; Copier's
source remains the original upstream. The CI workflow is customized for the OSS
artifact and local Lua/OpenSSL test dependency. Review these local changes when
updating the template. No GitHub repository/settings automation was run.

## Separate-driver timer validation

Run `make validation-timer` to build the standalone development-only helper at
`dist/validation/schlage_validation_timer.c4z`. Its source is under
`tools/validation_timer`, outside the release `drivers/` tree. It is not included
in the OSS driver bundle. The package contains a direct Lua script with no shared
modules, account access, networking, persistence, lock commands, or bindings.

Import it into Composer as Schlage Validation Timer on the same CORE 1 project.
Run Start Probe, immediately switch to Schlage Account and run Sign In during
the 15-second window, then return to the probe Properties after it completes.
Record Started/Finished UTC, elapsed milliseconds, callback count, maximum gap,
maximum extra delay, and skipped intervals, together with the account sign-in
log/timings. Stop Probe cancels a run. The result is a measurement rather than an
automatic pass verdict. Remove the helper when hardware validation is finished.

The local probe lifecycle test covers normal jitter, delayed/skipped callbacks,
cancellation, clock discontinuity, and destruction. Local tests cannot complete
the controller timer-responsiveness gate.
# Device normalization

The public device registry is keyed by cloud device ID, not display name. Its
exact Wi-Fi protocol allowlist is `be489wifi`, `be489wifi2`, and `be499wifi`.
Other identifiers remain visible in discovery as unsupported; no family-prefix
match permits BLE, bridge, lever, or future transport variants. Recognizing a
protocol identifier does not establish tested hardware compatibility; see
`hardware-validation.md` for actual controller and lock observations.

Normalized snapshots retain only ID, name, model/type, support and connectivity
flags, bolt/fault state, and validated battery telemetry. Missing or unrecognized
bolt state becomes unknown, including strings resembling numeric state codes.
Battery percentage and coarse low-battery state are independent. A successful
empty listing clears the registry; malformed/failed listings preserve it. Older
concurrent results and obsolete account generations cannot replace newer data.

## Bindings, polling, and companion handoffs

`registry.lua` adapts Nuheat's stable dynamic bindings. Its namespace includes
an SHA-256 digest of the Cognito pool and canonical account username. The
username itself is not persisted in public binding records. Connections remain
stable through renames, disappearance, and reappearance.

The installer places companions in Composer, with no room-count restriction.
`selection.lua` populates each companion's Schlage Account and Lock Properties
dropdowns and persists only the chosen project-account ID, cloud scope, and
cloud device ID. `catalog.lua` sends public catalogs to recognized companion
drivers and validates explicit selection before binding. It rejects another
companion's already-assigned physical lock and obsolete catalog requests.
Changing selection releases old queued commands, disconnects the old input,
and rejects mismatched handoffs. Normal polling never creates project devices.

`poller.lua` owns the scheduled read flight, retry/cooldown and independent stale
deadline. Manual reads share its active flight. A valid empty listing is a
successful read; transport and parsing failures retain the previous registry.
An HTTP 401 read permits one forced token refresh and one read retry. HTTP 429
delays apply through a shared request-eligibility gate. `retry_after.lua` parses
integer seconds and all three HTTP-date formats from RFC 9110 without local
timezone conversion. Writes and readbacks also use this gate, with another
eligibility check after asynchronous authentication finishes.

`bridge.lua` sends only public allowlisted snapshots to verified bound Schlage
companions. Child-generated subscription nonces and increasing handoff sequences
reject responses from earlier child lifecycles or bindings. Account restart
requests a new subscription. Public identities are retained for safe matching;
online and reported bolt state are not persisted. `companion.lua` keeps the last
observed bolt independent of offline status and rejects stale handoffs.

Local regression coverage includes account isolation, repeated selection,
multiple locks in one room, duplicate names, rename/removal/reappearance,
restart recovery, stale replies, deselection, cancellation on reselection,
actual Properties callbacks, simulated polling/backoff/staleness, normalized
secret-free catalogs/handoffs, and rebind/unbind. Composer installation and UI
presentation still require real-controller validation.

## Command reconciliation and public-source review

The account is a standalone combo driver. The lock is a protocol driver with
an external standard lock proxy and must not declare combo true. The original
scaffold's lock combo flag was removed when investigating absent Navigator
visibility; the metadata regression now distinguishes these roles and verifies
the proxy's LOCK connection. See the official introduction's driver terminology
and the pinned ESPHome lock XML. Local build versions use UTC, matching CI.

Live commissioning also requires the generic Door Lock Navigator device. Bind
its relay input to the standard lock proxy's Lock State output. The current
project export confirms protocol 36 has standard lock proxy 37 bound at 5001;
the user identified the missing generic device after proxy creation alone did
not populate Locks & Sensors. Account selection remains automatic, while this
Navigator binding is an installer step. Physical commands and feedback still
require hardware validation.

`commands.lua` keeps command queues in memory only, serializes each lock, and
coalesces only unsent intents. Explicit account/child lifecycle events cancel
pending work. Native `C4:GetTickCount()` supplies monotonic uptime for queue age,
confirmation deadlines, polling freshness, and cooldowns. UTC wall time is used
for token expiry and HTTP-date conversion. Properties display controller local
time with its time-zone abbreviation; the LAST_SUCCESSFUL_UPDATE programming
variable retains its UTC format.

`client.lua` advances each device's response revision at write dispatch, even
when that write later times out or is rejected. Reads also carry issue sequence
numbers within a revision. Old polls, late reads, and pre-removal responses
cannot replace a newer observation or resurrect a removed lock. Accepted device
observations can update presentation independently of command confirmation;
HTTP acceptance alone does not confirm a bolt position. Once the write callback
has completed, background discovery can confirm a command using a client-accepted
observation issued after its dispatch. Retained pre-write cache entries cannot
confirm it. Individual checks run at 1, 3, 5, 7, 11, 15, and 29 seconds, with
elapsed offsets skipped when a read runs slowly and no overlapping readbacks.
Readback starts before
the absolute 30-second deadline and pending transfers are cancelled at it.

The unavailable private review-driver checklist is not claimed as completed.
The public review basis is the pinned template, Nuheat account/binding patterns,
ESPHome lock proxy patterns, pinned pyschlage protocol behavior, official
[DriverWorks API](https://snap-one.github.io/docs-driverworks-api/) and
[XML reference](https://snap-one.github.io/docs-driverworks-xml/), and
[RFC 9110 Retry-After](https://www.rfc-editor.org/rfc/rfc9110.html#section-10.2.3).
No generic Nuheat write-retry or optimistic-state policy is applied to a lock.


## Native lock notification lifecycle

The native lock adapter follows the initialization/change split in the official
[Control4 lock SDK sample](https://github.com/snap-one/drivers-template-code-public/blob/50eee83dd690ef6724e4162f7e557d03a57b9b07/proxies/lock_proxy/lock_device_class.lua).
The first reported snapshot initializes the native proxy with
LOCK_STATUS_INITIALIZE. Subsequent observed position/fault changes send
LOCK_STATUS_CHANGED with LOCK_STATUS, LAST_ACTION_DESCRIPTION, SOURCE, and
MANUAL=false (the SDK default; REST does not identify a manual cause).
Repeated snapshots, telemetry-only changes, and HTTP command acceptance do not
produce movement notifications. A native proxy rebind reinitializes its current
reported state. Clearing/reassigning a selected lock clears the old display
without fabricating a movement event. Account polling still determines the
latency of observations made outside this driver. Actual app subscription
behavior requires controller validation; the C4 shim does not implement it.
