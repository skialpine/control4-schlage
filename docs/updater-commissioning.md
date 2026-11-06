# Updater commissioning

The local bootstrap packages are version **2026110601**. The first published
development release is **v2026110602-beta.1**, packaged as version **2026110602**.
The bootstrap shares source with that first release and has an older XML
version so the release updater can be exercised immediately. It does not contain
the later confirmation improvements. It is not a production release.

The main OneDrive Control4 folder and Drivers subfolder now contain the latest
published version **2026110606** for direct installation. The optional older
bootstrap is in **Bootstrap-2026110601** if testing an immediate automatic
upgrade; otherwise install the latest files directly and check for future
updates through the account.

1. From installed version 2026110605, use the update action below to test
   upgrading to **v2026110606-beta.1**. Alternatively install both latest `.c4z`
   files directly with Composer's Add or Update Driver. The optional older
   bootstrap remains available for a first update test.
2. Keep the existing Schlage account sign-in, physical-lock selections, and
   generic Door Lock relay bindings. Confirm they are still present.
3. On Schlage Account, select **Update Channel: Prerelease**. The setting is
   shared with installed Schlage companions.
4. Run **Check for Updates**. Observe **Update Status**, **Last Update Check**,
   and the account's Lua output. The companion package is installed first,
   followed by the account package.
5. Reopen both Properties pages and verify Driver Version **2026110606**.
   Verify credentials remain saved, the account signs in, and the selected
   lock and generic Door Lock control still match the physical bolt.
6. Leave Prerelease selected to receive further development releases, or select
   Stable to exclude them. Automatic Updates Off stops scheduled checks; a
   manual check still works.

No lock/unlock action is issued by the updater itself. Perform the initial
update check with no command in progress. Pending/unsent intents are not
persisted across driver reloads. The fallback ordering also keeps the account
last when a controller does not implement GetDriverFileName.

Source tests, packaging checks, and mock Director TCP update ordering are
verified locally. The user confirmed automatic installation of 2026110603
overnight and explicitly verified both installed versions as 2026110606. Both
Composer Documentation tabs open and read correctly. Native command feedback
and external locked/unlocked app updates are verified on CORE1 / OS 3.4.3.
CORE5 / OS 4.3, broader fault/outage tests, and the rollback rehearsal remain
open. Properties local-time formatting has not been separately reported.

## One-lock rollback rehearsal

Use the CORE1 development project and one existing generic Door Lock tile.
Keep the Schlage account/companions and Home Assistant integration installed.
The user has confirmed HA is available and working; its current provider and
connection must be identified from a fresh project before changing wiring.

1. Save the current Composer project as
   `Projects/lock test-before-rollback-2026110606.c4p` in the OneDrive Control4
   folder. Keep the older project file as well. The earlier saved export
   predates the final Navigator setup and is not the rehearsal checkpoint.
2. Record the generic Door Lock device name/ID and its current relay input,
   native Schlage provider/output, selected physical lock, and working HA
   provider/output. Confirm that the HA provider is available in this same
   project and uses the compatible connection class. Stop before rewiring if
   that provider is absent; record the actual arrangement first.
3. Wait until this lock has no queued or pending command. Temporarily connect
   only the chosen generic Door Lock input to its working HA provider. Retain
   the native provider details and all existing driver instances/programming.
4. Through that tile, verify one Lock and Unlock using HA. Confirm the intended
   physical bolt moves and the tile reports its observed state. Record pass
   or the exact discrepancy.
5. Reconnect the same input to the recorded native Schlage output. Verify
   native Lock/Unlock and a physical-turn state update with the tile visible.
   Allow polling/cloud time for the physical turn.
6. Save the restored native project separately as
   `Projects/lock test-after-rollback-2026110606.c4p`. Record the test lock, HA
   control/feedback result, native restoration result, and whether enrollment
   and saved account settings were retained.

Task 6.4 is complete only after the binding switch, HA control/feedback, and
native restoration have actually passed. Saving a backup or confirming HA
availability alone does not complete the rehearsal. This procedure uses
existing driver bindings and does not require resetting or re-enrolling locks.
