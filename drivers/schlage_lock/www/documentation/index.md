# Schlage Lock

Add one **Schlage Lock** driver per physical lock in the desired Composer room.
Open its **Properties** page and select the physical device from the **Lock**
dropdown. With a single account driver, **Schlage Account** is selected there
automatically. With several account drivers, choose the account first. The
account connection is made automatically. Navigator display uses a separate
generic **Door Lock** device and its relay binding, described below.

Several lock drivers can be placed in the same room, each selecting a different
physical lock. You can also place them in separate rooms. Placement does not
restrict the dropdown. A lock already assigned to another companion is not
available for a duplicate assignment.

Selections persist across restart and follow lock renames by stable ID. If a
selected lock disappears it is marked unavailable; another lock is never chosen
automatically. Changing account or selecting a different lock takes the
companion offline and cancels pending work for the old selection before
connecting the new one. Choose **Select a lock** to clear an assignment.
**Refresh Available Locks** reloads the dropdown from the account's discovery.
**Selection Status** reports whether discovery or a lock choice is needed.

The standard Control4 lock proxy accepts Lock, Unlock, and Toggle through
Navigator and Composer programming. Keep the existing Home Assistant bridge and
its bindings available during development. Basic Lock and Unlock have been
reported working with matching state on CORE 1 / OS 3.4.3. Rapid command
handling, faults, and recovery still require live validation.

Properties report online availability, the observed bolt state, name/model,
battery percentage, coarse low-battery state, and last successful update.
Unknown and jammed state remain distinct. Missing battery fields show Not
provided. Offline status does not imply that the bolt moved. **Refresh State**
requests the account's current public snapshot; scheduled reads belong to the
account. No authentication credentials or tokens are passed to this driver.

## Navigator visibility

This companion provides the Control4 lock protocol and standard lock proxy. The
Navigator tile requires a generic **Door Lock** device:

1. Add a generic **Door Lock** from **My Drivers → Motorization** to the room.
1. In **Connections**, bind that device's relay input to the Schlage lock
   proxy's **Lock State** relay output.
1. Rename the generic Door Lock to the desired displayed name.
1. Run **File → Refresh Navigators**. Use the room's **Navigator → Locks &
   Sensors → Modify** controls to set the generic Door Lock's visibility.

Repeat for each physical lock, including several locks in the same room. The
account and physical-lock dropdowns remain on the Schlage Lock companion; the
generic Door Lock supplies the room's Navigator tile. Test both the command path
and observed-state feedback before relying on that tile in automation.

The initial development preview incorrectly retained the standalone combo flag
on the lock driver. That flag is removed in build 20261106. Update the existing
lock driver first. Older standalone instances may need replacement to create the
standard lock proxy and its relay output; retain the project backup and existing
programming while investigating. A newly added instance in the CORE 1 test
project has a separate, bound standard lock proxy. That proxy alone was not
listed in Locks & Sensors; the user identified the additional generic Door Lock
and binding step, then confirmed that Lock and Unlock operate the bolt and match
its state.

## Command outcomes and programming

**Command Outcome** shows queued, pending, confirmed, unconfirmed, fault,
expired, cancelled, authentication_failed, or rejected (with a reason when
available). Acceptance by the cloud does not confirm physical state. Pending
commands never change the reported bolt optimistically. A reported jam maps to
the proxy's fault status; missing or unrecognized bolt state maps to unknown.
Toggle is rejected when the current state is unknown, jammed, or offline.

The generic Door Lock sends Toggle for each tap. With fresh known state, a
second tap during a pending move reverses the latest live requested target, even
before cloud state catches up. When no live target exists it toggles the
reported bolt state. Failed or expired targets are ignored. Pending targets
never change the displayed observed bolt state optimistically.

Commands for one lock never overlap while a cloud write is in flight. Once that
write is acknowledged, the newest queued explicit action can proceed without
waiting for the older command's state confirmation. Older readback is cancelled
and cannot confirm the new command. A failed or uncertain write retains its
bounded reconciliation wait. The newest command still needs a fresh reported
state before it is confirmed.

For slow responses, set **Log Mode** to **Print** or **Print and Log** and **Log
Level** to **3 - Info** on both the companion and account. The companion logs
incoming proxy commands. The account logs command sequence/action, receipt,
dispatch, cloud response, readback, and outcome with elapsed milliseconds from
receipt. These lines exclude cloud IDs, credentials, and raw responses. Compare
cloud acknowledgement time with confirmation time to locate the delay; the
normal account polling interval does not delay initial command dispatch.

Unsent commands expire after 30 seconds. Confirmation ends at 30 seconds from
dispatch. Timeout/rejection does not cause an automatic lock/unlock retry.
Cancellation cannot recall a request already sent to the cloud.

Read-only protocol variables are available in Composer:

| Variable               | Meaning                                                           |
| ---------------------- | ----------------------------------------------------------------- |
| ONLINE                 | Current account/device availability, independent of bolt position |
| BOLT_STATE             | locked, unlocked, jammed, or unknown                              |
| JAMMED                 | True when the latest observed bolt state is jammed                |
| BATTERY_PERCENT        | Percentage, or -1 when unavailable                                |
| BATTERY_KNOWN          | Whether BATTERY_PERCENT has a supplied reading                    |
| LOW_BATTERY_STATE      | normal, low, or unknown; independent of percentage                |
| LAST_SUCCESSFUL_UPDATE | UTC timestamp of the last accepted device observation             |
| COMMAND_OUTCOME        | Latest command outcome                                            |
| REQUESTED_ACTION       | Explicit lock/unlock intent, when resolved                        |

PIN management, schedules, history, door-open status, MQTT, and offline control
are not advertised or implemented. Full validation of polling, rapid changes,
faults, and recovery remains pending.

The **Last Update** property uses the controller local time and time zone.

The native proxy is initialized from the first reported snapshot after startup
or physical-lock reassignment. Later bolt changes include a **Last Action
Description**, such as `Reported lock state: unlocked`, and source
`Schlage Home`. Repeated polls and telemetry-only changes do not create movement
events. A reported position matching a pending Control4 action uses
MANUAL=false. Other online locked/unlocked changes use MANUAL=true to mark an
observation outside that pending action. This is an inferred external-change
classification; REST does not identify whether a key, keypad, app, or another
automation moved the bolt. Leave the app tile visible when testing live state
updates. Manual/app changes are detected by polling and may take the configured
polling interval plus cloud reporting time.

## Updates and diagnostics

**Automatic Updates** and **Update Channel** are shared with the account and
other companions. **Stable** excludes development releases; choose
**Prerelease** while commissioning published preview builds. The account
performs the downloads and installations, with companions updated before the
account itself. Use the account's **Check for Updates** action and its **Update
Status** for manual checks and feedback.

**Actions → Diagnostics Snapshot** prints local versions, online/bolt/battery
state, command outcome, and update/logging settings even with Log Mode Off. It
excludes credentials, cloud lock IDs, scope hashes, names, and raw responses,
and sends no external telemetry.

## Composer events and conditions

The companion adds **Online**, **Offline**, **Locked**, **Unlocked**,
**Jammed**, **Low Battery**, **Command Confirmed**, and **Command Failed**
events. IDs stay stable across driver reloads so existing Composer programming
remains attached. Repeated observations do not repeat an event. Initial
synchronization and a different selected lock do not claim a physical bolt
transition. Command Failed covers rejected, unconfirmed, expired,
authentication-failed, and fault outcomes; it does not mean an already
transmitted command was recalled.

Conditions ask whether the selected lock is **online**, **locked**,
**unlocked**, **jammed**, or has **low battery**. Bolt and battery conditions
require online data, so old state retained during an outage is not treated as a
current condition. A locked bolt does not establish whether the door is open.
Navigator still uses the separately bound generic Door Lock.

## Attribution

Built with the Finite Labs Control4 driver template v0.9.74 (AGPL-3.0). This is
an independent open-source project, not an official Schlage driver. Standard
lock proxy patterns are adapted from Finite Labs Control4 ESPHome (AGPL-3.0).
See the packaged upstream notices for pinned revisions.
