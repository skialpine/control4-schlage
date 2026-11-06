# <span style="color:#109EFF">Changelog</span>

<!--
Template for a new release entry (copy below the heading, fill in, uncomment):

## v[Version] - YYYY-MM-DD

### Added
- Added

### Fixed
- Fixed

### Changed
- Changed

### Removed
- Removed
-->

## v2026110607-beta.1 - 2026-11-06

### Added

- Account-wide Low Battery Push Notifications On/Off, local reminder time and
  battery threshold for all discovered locks, with once-per-local-date
  suppression preserved across reloads.
- Automatic Schlage-owned Control4 notification entries, visible Control4 lock
  names in alert text, a Daily Low Battery Alert Composer event and message
  variable, and a separately labeled test action. No manual agent programming is
  required; controller push-delivery validation is pending.

## v2026110606-beta.1 - 2026-11-06

### Fixed

- Distinguish observed changes outside a matching pending Control4 command when
  setting the native lock notification MANUAL flag. Keep initialization,
  fault/unknown, duplicate-state, and command-confirmation behavior separate.

## v2026110605-beta.1 - 2026-11-06

### Fixed

- Initialize the native lock proxy on synchronization, reload, and reassignment;
  send change notifications only when the reported bolt status changes.
- Include a readable Last Action description and public source in native lock
  change notifications for Navigator presentation.

## v2026110604-beta.1 - 2026-11-06

### Changed

- Display Last Session Renewal, Last Update Check, and Last Update in the
  controller local time with its time-zone abbreviation.

## v2026110603-beta.1 - 2026-11-06

### Fixed

- Check reported state at five and eleven seconds as well as the existing
  confirmation times, reducing gaps while keeping a seven-read maximum.
- Allow fresh background discovery to confirm a completed command without
  waiting for the next individual read. Pre-write and superseded responses
  cannot confirm commands, and rejected writes remain rejected.

## v2026110602-beta.1 - 2026-11-06

### Added

- GitHub release updates with shared automatic-update/channel settings, one
  account coordinator, manual checks, and lasting update feedback.
- Local allowlisted Diagnostics Snapshot actions on both drivers.
- Stable Composer events and conditions for reported availability, bolt/fault,
  low battery, and command outcomes, without movement events on initial sync.
- Independent Composer icons for the account and lock drivers.
- Same-day release revisions and tag/package version consistency checks.

### Fixed

- Rapid generic Door Lock toggles reverse the pending target while retaining
  observed-state reporting and command expiry rules.
- Newer explicit commands can follow successful cloud acknowledgement without
  waiting for superseded confirmation reads.
- Unchanged public lock identities are no longer persisted on every snapshot.
