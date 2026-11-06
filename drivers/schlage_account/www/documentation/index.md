# Schlage Account

This development driver signs in to Schlage Home directly from Control4,
discovers locks, and shares polled status with companion drivers. The companion
exposes native lock/unlock/toggle commands with bounded reported-state readback.
This is a development preview; basic Lock/Unlock with matching physical state
has been reported working, while rapid changes and recovery remain under test.

Native authentication, discovery, renewal, and restart recovery have been tested
on CORE 1 / OS 3.4.3.741643-res, with two Encode Plus BE499WB locks. Captured
firmware is main 5.0.1300214 and Wi-Fi 3.22.0.1. Polling, companion installation
and command behavior still require full live validation. CORE 5 / OS 4.3 is
untested. The account package requires OS 3.4.1 or later.

## Installation and sign-in

1. Keep the current Home Assistant bridge, bindings, and automation available.
1. Add `schlage_account.c4z` to the intended development Composer Pro project.
1. Run **Check Crypto**. **Crypto Status** must report native acceleration and
   secure randomness. If it fails, record the status and stop this controller's
   validation.
1. Enter **Schlage Email**, then **Schlage Password**, using the account
   associated with the Schlage Home app. Both fields are masked, saved through
   encrypted controller persistence, and cleared after entry. Changing the email
   discards the previously entered password; enter the password again afterward.
   **Credentials** confirms when both values are saved and shows a masked email,
   such as `Saved for j***@example.com`. Saved credentials still require a
   successful Sign In to establish that they are valid.
1. Run **Sign In**. **Driver Status** should become `signed_in`. The driver then
   performs one discovery request. **Discovered Locks** shows a compact count,
   such as `2 locks found`. No lock companions are created.
1. Record **SRP Public Time (ms)** and **SRP Proof Time (ms)**. Either phase
   exceeding 250 ms blocks authentication on that controller. Confirm another
   driver's timer remains responsive during sign-in.

## Renewal, restart, and errors

A valid session is renewed 60 seconds ahead of expiry. **Renew Session**
exercises renewal on demand. A successful renewal that omits a refresh token
keeps the existing one. After driver/controller restart, the driver renews from
encrypted persistence without requesting the password again. **Last Session
Renewal** records the UTC time of the last successful refresh-token renewal
during this driver run. It updates on manual renewal, automatic renewal, and
successful restart recovery. Sign In does not set it. Check this persistent
result after running Renew Session; the brief `renewing` status can complete
before you return to Properties. SRP timings remain unchanged during renewal.
The explicit Renew Session action also prints its start and success/failure in
the Lua tab, even with Log Mode Off. It prints the selected logging mode/level
and active output flags so logging configuration can be verified. Log Level
controls verbosity; Log Mode selects Print, controller Log, or both.

Transient authentication failures enter `retry_wait` with bounded exponential
backoff. Rate-limit errors use a supplied numeric or HTTP-date Retry-After
delay, or 60 seconds when absent/invalid. Discovery runs after successful
sign-in/renewal and on the polling interval; **Discover Locks** requests an
immediate read. A discovery error reports a retrieval failure, rather than an
empty account. Run **Discover Locks**, then open the **Lua** tab for the
complete list, one lock per line with its name, cloud device type, and model
when provided. This explicit action prints the list even with Log Mode Off.
Automatic sign-in and renewal discovery update the count without printing the
list. Discovery output contains only these public fields, with no raw cloud
payloads or authentication data.

Permanent credential/refresh rejection reports `sign_in_required` and stops
automatic authentication. Correct credentials if needed, then explicitly run
**Sign In**. Unsupported challenges require completing the corresponding account
steps in Schlage's app; this build does not provide MFA/password-reset prompts.
**Sign Out** cancels pending work and clears persisted credentials and session.
Clearing an entry field is not a Sign Out action.

## Companion selection and polling

Install both account and lock `.c4z` files into Composer's local driver library.
Sign in on the account and confirm successful discovery. Add a **Schlage Lock**
driver in each desired room for each physical lock. On that companion's
**Properties** page, choose **Schlage Account** and then choose its physical
lock from the **Lock** dropdown. A new companion chooses a single available
account automatically; several accounts require an explicit choice. The
connection is made automatically after lock selection.

For each lock's Navigator tile, also add a generic **Door Lock** in the desired
room and bind its relay input to the Schlage lock proxy's **Lock State** relay
output. Run **File → Refresh Navigators**, then configure the generic Door Lock
under the room's **Navigator → Locks & Sensors** settings. See the Schlage Lock
documentation for the complete setup. Automatic account binding does not create
this generic Navigator device.

Any room may contain multiple companions, each selecting a different physical
lock. Room placement does not determine lock identity. Already assigned locks
are excluded from another companion's available choices. Renames retain the
selected cloud ID. Removed locks show unavailable and go offline without
silently selecting another lock. Changing account or lock cancels old pending
work and rejects handoffs for the previous selection. Existing bound companions
retain their identities when upgraded.

**Refresh Available Locks** on the companion reloads account and lock choices.
The list also follows the account's discovery updates. No account-wide bulk
placement action is needed.

The exact recognized Wi-Fi device types are `be489wifi`, `be489wifi2`, and
`be499wifi`. Other types are listed as unsupported and cannot be selected by a
companion. Recognition is not a tested-hardware compatibility claim.

**Polling Interval (seconds)** defaults to 30, with a 15-second minimum. Only
one scheduled account read runs at a time. Transient failures back off with
jitter between 5 and 300 seconds. Rate limits take precedence over polling and
block cloud request eligibility for the server's delay. A valid empty account
removes locks from the current listing; a retrieval failure preserves the
previous listing. After 120 seconds without a successful account read,
companions go offline. An explicitly disconnected lock goes offline immediately.
Intervals longer than 120 seconds will therefore allow data to become stale
between reads.

Companions request current state at startup and after rebinding. Handoffs
contain public state and telemetry only. Rebinding, account changes, or restart
invalidate earlier subscriptions so late messages cannot restore obsolete state.

For command timing, enable **Print** or **Print and Log** at **3 - Info** on
this account and its lock companion. Account Lua output includes
`Schlage command` lines for receipt, dispatch, cloud acknowledgement/failure,
readback, and completion, using elapsed milliseconds. Acknowledged writes allow
the newest queued explicit action to replace older confirmation reads. Failed or
uncertain writes retain the reconciliation wait, and cloud rate limits and
30-second queue expiry still apply. HTTP acceptance alone never confirms state.

## Driver updates

Install the updater-enabled account and lock files once through Composer. After
that, **Automatic Updates** defaults to **On** and **Update Channel** defaults
to **Stable**. Choose **Prerelease** to receive published development builds.
These two settings stay the same across installed Schlage drivers. The account
with the lowest project ID coordinates checks after 60 seconds, then every six
hours. A pending lock command delays starting a check.

Run **Actions → Check for Updates** for an immediate check, even with automatic
checking Off. **Update Status** and **Last Update Check** provide lasting
feedback; the manual action also prints to Lua with logging Off. The updater
downloads only installed Schlage packages, installs companions first and its own
account package last, and leaves credentials and lock selections in controller
persistence. A driver update can interrupt a current readback, and expired
command intents are never resumed after reload.

Updates come from published releases of
[skialpine/control4-schlage](https://github.com/skialpine/control4-schlage), not
from arbitrary commits or new versions of the source template. A release uses a
numeric **YYYYMMDDRR** version, where RR increases for successive releases on
one date. Every stable or prerelease publication gets a new numeric revision.
Until a public release source is available, checks report a failure and the
driver remains usable; this is independent of Schlage authentication.

## Local diagnostics

**Actions → Diagnostics Snapshot** prints a local report of versions, polling,
command counts, logging, crypto timings, and update settings. It works with Log
Mode Off. The report contains no email, password, token, cloud lock ID, account
scope, user-defined lock names, or raw cloud response. It uploads nothing. Keep
the account and lock reports when investigating commissioning.

## Diagnostics and hardware gate

Log Mode defaults to Off. If requested for validation, enable Print or Log and
select a Log Level; logging automatically turns off after three hours. Even at
Ultra, raw URL and generic handler tracing remain disabled. Diagnostic output
contains operation categories, counts, and timings, without credentials, tokens,
SRP private values, CAT/SAT, identity headers, or PINs. Do not enable raw
tracing manually or send raw account payloads or project exports for review.

Record sanitized observations in `docs/hardware-validation.md`: exact OS build,
TLS success, entropy and acceleration availability, both crypto durations,
other-driver timer responsiveness, discovered model types, renewal, restart
recovery, and inspection of logs and a local project export for plaintext
secrets. All measurements must come from the controller. Local fixture tests do
not satisfy this gate. The native authentication gate passed on the CORE 1
combination above. Integrated lock operation and failure recovery remain
pending.

## Command behavior

Commands route through the bound account connection to an explicitly recognized
Wi-Fi lock. Offline or unsupported targets are rejected. Toggle requires a fresh
known locked/unlocked state and resolves once to an explicit lock or unlock.

Each lock has one active command and at most the newest unsent intent. Unsent
intents expire 30 seconds after the user's request. They are never persisted.
Sign-out, account changes, removal, disconnection, unbinding, or a replacement
companion subscription cancel pending work. Cancellation cannot recall a request
already transmitted to the cloud.

HTTP acceptance does not change the observed bolt state. Reported-state reads
run approximately 1, 3, 7, 15, and 29 seconds after dispatch, with an absolute
30-second deadline that includes network/authentication time. A matching read
reports confirmed; a jam reports fault; missing or mismatched state can end as
unconfirmed. A definite cloud rejection remains rejected even if a later read
finds the target position. Timeouts, 401, and 429 responses never cause
automatic mutation replay. Rate limits can prevent readback before the deadline.

Confirmed means that a subsequent cloud read reported the requested bolt state.
Physical lock behavior and cloud reporting latency must still be checked on
hardware. No optimistic position change is sent to Navigator.

## Rollback

Sign Out and remove the development companions and account driver. Retain or
restore the original Home Assistant bridge bindings. This build does not change
lock configuration or require lock reset/re-enrollment.

## Attribution

Independent open-source project, not an official Schlage driver. Built with
[Finite Labs' Control4 driver template](https://github.com/finitelabs/control4-driver-template)
v0.9.74 (AGPL-3.0). Schlage protocol references are
[pyschlage](https://github.com/dknowles2/pyschlage) and
[pycognito](https://github.com/NabuCasa/pycognito) (Apache-2.0), with
[Hubitat Schlage](https://github.com/schwark/hubitat-schlage) (MIT) as a
cross-check. Pinned revisions are recorded in `docs/reference-revisions.json`.
License texts and upstream notices are included under `www/licenses` in the
driver package.
