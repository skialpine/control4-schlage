# Updater commissioning

The local bootstrap packages are version **2026110601**. The first published
development release is **v2026110602-beta.1**, packaged as version **2026110602**.
The bootstrap shares source with that first release and has an older XML
version so the release updater can be exercised immediately. It does not contain
the later confirmation improvements. It is not a production release.

The main OneDrive Control4 folder and Drivers subfolder now contain the latest
published version **2026110605** for direct installation. The optional older
bootstrap is in **Bootstrap-2026110601** if testing an immediate automatic
upgrade; otherwise install the latest files directly and check for future
updates through the account.

1. From installed version 2026110604, use the update action below to test
   upgrading to **v2026110605-beta.1**. Alternatively install both latest `.c4z`
   files directly with Composer's Add or Update Driver. The optional older
   bootstrap remains available for a first update test.
2. Keep the existing Schlage account sign-in, physical-lock selections, and
   generic Door Lock relay bindings. Confirm they are still present.
3. On Schlage Account, select **Update Channel: Prerelease**. The setting is
   shared with installed Schlage companions.
4. Run **Check for Updates**. Observe **Update Status**, **Last Update Check**,
   and the account's Lua output. The companion package is installed first,
   followed by the account package.
5. Reopen both Properties pages and verify Driver Version **2026110605**.
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
overnight, with subsequent account discovery still returning both locks.
Local-time Properties formatting and live Navigator state notifications on
2026110605 remain live checks. Keep the app tile open while moving the bolt,
and confirm that it updates without a second tap or navigating away.
