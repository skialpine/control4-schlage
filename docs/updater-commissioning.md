# Updater commissioning

The current maintenance prerelease is **v2026110801**, packaged as
**2026110801**, using template v0.9.80 with credential-safe logging integration.
It requires the Prerelease channel and remains under live investigation.
Stable/Latest remains **v2026110608**. See
[maintenance release notes](releases/2026110801.md).

The initial stable release is **v2026110608**, packaged as version
**2026110608**. Its runtime matches the tested **2026110607** prerelease; the
stable publication updates the version and documentation. Outage/recovery
testing is deferred, and scheduled daily battery alert follow-up checks remain
unverified on hardware. See [release notes](releases/2026110608.md).

The main OneDrive Control4 folder contains the latest published version
**2026110801** for direct installation. Future deliveries go to that root folder
only. **Do not copy or overwrite packages in the Drivers subfolder**: Composer
manages its local driver database. Externally copying there can make the
versions appear equal while Composer retains an older property layout. Import or
sync through Composer when its local driver definition needs updating. The
optional older bootstrap in **Bootstrap-2026110601** is a historical test build,
not the recommended install.

1. From an earlier installed version, use the update action below to test
   upgrading to **v2026110801**. Alternatively install both latest `.c4z` files
   directly with Composer's Add or Update Driver. The optional older bootstrap
   remains available for a first update test.
1. Keep the existing Schlage account sign-in, physical-lock selections, and
   generic Door Lock relay bindings. Confirm they are still present.
1. To test maintenance version 2026110801, select **Update Channel:
   Prerelease**. Stable excludes it and retains the accepted 2026110608 release.
   The setting is shared with installed Schlage companions.
1. Run **Check for Updates**. Observe **Update Status**, **Last Update Check**,
   and the account's Lua output. The companion package is installed first,
   followed by the account package.
1. Reopen both Properties pages and verify Driver Version **2026110801**. Verify
   credentials remain saved, the account signs in, and the selected lock and
   generic Door Lock control still match the physical bolt. If the new battery
   settings are missing despite this version, import the account file from the
   main Control4 folder using **Driver → Add or Update Driver** to refresh
   Composer's local definition. Reopening Composer alone did not resolve the
   observed stale layout; reloading the driver did.
1. New releases start as prereleases and become Stable/Latest only after the
   user confirms live testing. Leave Stable selected to receive accepted stable
   releases, or select Prerelease for test builds. Automatic Updates Off stops
   scheduled checks; a manual check still works.

On **Schlage Account**, **Low Battery Push Notifications** applies to all locks
on that account. It defaults Off; the default reminder time is 09:00 local and
the threshold is 20 percent. Enable it and run **Test Battery Alert** to check
delivery without changing a lock or consuming its daily allowance. A
user-supplied CORE5 screenshot confirmed a TEST notification containing the
visible Control4 generic Door Lock name and its supplied 100% battery reading.
Automatic daily delivery from a genuinely low battery remains covered by local
policy tests; that live scenario has not yet been observed.

No lock/unlock action is issued by the updater itself. Perform the initial
update check with no command in progress. Pending/unsent intents are not
persisted across driver reloads. The fallback ordering also keeps the account
last when a controller does not implement GetDriverFileName.

Source tests, packaging checks, and mock Director TCP update ordering are
verified locally. The user confirmed automatic installation of 2026110603
overnight and explicitly verified both installed versions as 2026110606. Both
Composer Documentation tabs open and read correctly. Native command feedback and
external locked/unlocked app updates are verified on CORE1 / OS 3.4.3. The user
also reports successful loading/basic operation on CORE5 / OS 4.3. Its current
exact build and broader cases are not separately recorded. Outage/recovery
testing is deferred and remains unchecked; rollback is closed by explicit user
acceptance. Properties local-time formatting has not been separately reported.

## One-lock rollback rehearsal

Use the CORE1 development project and one existing generic Door Lock tile. Keep
the Schlage account/companions and Home Assistant integration installed. The
user has confirmed HA is available and working; its current provider and
connection must be identified from a fresh project before changing wiring.

1. Save the current Composer project as
   `Projects/lock test-before-rollback-2026110606.c4p` in the OneDrive Control4
   folder. Keep the older project file as well. The earlier saved export
   predates the final Navigator setup and is not the rehearsal checkpoint.
1. Record the generic Door Lock device name/ID and its current relay input,
   native Schlage provider/output, selected physical lock, and working HA
   provider/output. Confirm that the HA provider is available in this same
   project and uses the compatible connection class. Stop before rewiring if
   that provider is absent; record the actual arrangement first.
1. Wait until this lock has no queued or pending command. Temporarily connect
   only the chosen generic Door Lock input to its working HA provider. Retain
   the native provider details and all existing driver instances/programming.
1. Through that tile, verify one Lock and Unlock using HA. Confirm the intended
   physical bolt moves and the tile reports its observed state. Record pass or
   the exact discrepancy.
1. Reconnect the same input to the recorded native Schlage output. Verify native
   Lock/Unlock and a physical-turn state update with the tile visible. Allow
   polling/cloud time for the physical turn.
1. Save the restored native project separately as
   `Projects/lock test-after-rollback-2026110606.c4p`. Record the test lock, HA
   control/feedback result, native restoration result, and whether enrollment
   and saved account settings were retained.

Task 6.4 is complete only after the binding switch, HA control/feedback, and
native restoration have actually passed. Saving a backup or confirming HA
availability alone does not complete the rehearsal. This procedure uses existing
driver bindings and does not require resetting or re-enrolling locks.
