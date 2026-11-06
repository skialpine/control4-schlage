# Spec Delta

## Purpose

Connect a Control4 installation directly to a Schlage Home account and share authenticated cloud access across its lock drivers.

## ADDED Requirements

### Requirement: GitHub release updates
The drivers SHALL reuse the template's GitHub Releases updater for installed packages, with shared automatic-update/channel settings, a manual check, readable status, and preserved credentials/selections. One account SHALL coordinate checks, waiting for its command queues to be idle. Release versions SHALL increase and match their packaged drivers.

#### Scenario: Stable automatic update
- **WHEN** automatic updates are On and a newer stable release is available while no lock command is pending
- **THEN** the coordinating account updates installed companion files before updating its own account file.

#### Scenario: Prerelease is not selected
- **WHEN** the update channel is Stable
- **THEN** prerelease GitHub releases are excluded.

#### Scenario: Shared setting changes
- **WHEN** the installer changes Automatic Updates or Update Channel on an account or companion
- **THEN** the other installed Schlage instances receive the same supported setting without broadcast loops.

#### Scenario: Update fails or driver is destroyed
- **WHEN** a release check fails or the coordinator is destroyed
- **THEN** the driver reports a sanitized failure or cancels its future update timers, respectively, without changing Schlage credentials or resurrecting expired lock intents.

### Requirement: Native account authentication
The account driver SHALL authenticate with Schlage's Cognito user pool from the controller using the account credentials and SHALL require no external authentication service or runtime bridge.

#### Scenario: Valid account
- **WHEN** the installer supplies valid Schlage Home credentials and starts sign-in
- **THEN** the controller completes authentication and makes account discovery available.

#### Scenario: Credentials or challenge rejected
- **WHEN** authentication fails permanently or requires an unsupported challenge
- **THEN** the driver reports a specific sign-in-required status and stops automatic credential attempts until the installer intervenes.

### Requirement: Protected authentication data
The driver SHALL mask credential-entry fields, encrypt persisted credentials and tokens, and exclude passwords, tokens, SRP private values, and lock PINs from logs, diagnostics, companion messages, and packaged examples.

#### Scenario: Diagnostic logging enabled
- **WHEN** an authentication request, response, or error is logged at any supported log level
- **THEN** secret values are absent or redacted while the operation and failure category remain readable.

### Requirement: Token lifecycle and restart recovery
The account driver SHALL renew tokens before expiry, preserve a valid refresh token when renewal omits a replacement, and resume from encrypted persisted credentials after restart. Concurrent requests SHALL share one authentication or renewal attempt.

#### Scenario: Restart with reusable refresh token
- **WHEN** the controller restarts with a valid stored refresh token
- **THEN** the driver renews the session and resumes discovery and polling without credential reentry.

#### Scenario: Refresh token revoked
- **WHEN** Cognito permanently rejects the stored refresh token
- **THEN** the driver invalidates the session, takes companions offline, and reports that installer sign-in is required.

### Requirement: Stable discovery and companion identity
The account driver SHALL discover supported Wi-Fi locks and expose a stable connection for each cloud device ID. Each installer-placed companion SHALL provide Properties dropdowns to select its account driver and a discovered physical lock, without requiring manual connection wiring or duplicating an assigned lock. Multiple companions SHALL be permitted in any room, and a successful account listing SHALL take removed locks offline.

#### Scenario: Discovery repeated after a lock rename
- **WHEN** the same selected cloud device ID is returned under a new name
- **THEN** the existing connection and companion are retained without a duplicate lock.

#### Scenario: Listing fails
- **WHEN** discovery fails or returns an unreadable response
- **THEN** the driver reports a retrieval failure without treating existing locks as deleted.

#### Scenario: Multiple locks in one room
- **WHEN** the installer adds two companions to the same room and selects a different discovered lock on each
- **THEN** each companion retains its own lock identity and controls only that selected lock.

### Requirement: Bounded polling and cloud recovery
The driver SHALL poll at a configurable interval with a 30-second default and 15-second minimum, avoid overlapping scheduled polls, respect rate-limit retry delays, and back off transient failures. It SHALL mark account data unavailable after 120 seconds without a successful account read.

#### Scenario: Cloud outage
- **WHEN** scheduled reads fail for more than 120 seconds
- **THEN** companions report offline and subsequent retries remain bounded until a successful read restores availability.

#### Scenario: Rate limit received
- **WHEN** the cloud returns HTTP 429
- **THEN** the driver honors Retry-After when valid, uses a bounded fallback delay otherwise, and blocks new polls and writes during that delay.

### Requirement: Lifecycle isolation
Signing out, changing accounts, resetting the driver, or destroying it SHALL cancel its timers and pending command intents and SHALL prevent late callbacks from restoring an obsolete account session or reporting old account data.

#### Scenario: Old response arrives after account change
- **WHEN** an in-flight request from the previous account completes after new credentials have been entered
- **THEN** its result cannot alter the current account, its lock bindings, or companion state.

### Requirement: Supported-device boundaries
The driver SHALL identify supported Encode-family devices explicitly, report unsupported models clearly, and document the controller/OS and lock models actually validated before release.

#### Scenario: Unknown device type discovered
- **WHEN** the account contains an unrecognized lock type
- **THEN** it is reported as unsupported and receives no lock commands through an automatically created companion.
