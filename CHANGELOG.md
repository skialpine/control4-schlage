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
