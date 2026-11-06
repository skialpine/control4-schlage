# Spec Delta

## Purpose

Present Schlage Wi-Fi locks as native Control4 locks with trustworthy command outcomes, fault states, and availability information.

## ADDED Requirements

### Requirement: Native lock interface
Each bound companion SHALL expose Control4's standard lock proxy and accept lock, unlock, and toggle commands from Navigator and Composer programming. The account driver SHALL own the shared cloud session.

#### Scenario: Navigator requests a lock
- **WHEN** the user requests Lock on an online supported companion
- **THEN** the driver sends an explicit lock request for that companion's cloud device ID through its bound account driver.

#### Scenario: Toggle with unknown state
- **WHEN** Toggle is requested without a fresh confirmed locked or unlocked state
- **THEN** the driver rejects the toggle and reports that current state is unavailable.

#### Scenario: Repeated generic Door Lock taps during a pending move
- **WHEN** a generic Door Lock sends another Toggle while a live, unrejected lock/unlock intent is pending and the reported bolt state is still fresh and known
- **THEN** the new toggle is resolved once as the opposite of the latest queued or in-flight target
- **AND** the previous target is not substituted for the reported physical bolt state, and failed or expired targets are not used as the baseline.

### Requirement: Explicit Schlage state mapping
The companion SHALL map Schlage states 1 and 6 to locked, 0 and 5 to unlocked, 2 and 4 to fault/jammed, and missing, invalid, or unknown values to unknown. Unknown or jammed values SHALL never be coerced to a successful locked or unlocked state.

#### Scenario: Jam reported
- **WHEN** an authoritative response contains lockState 2 or 4
- **THEN** the Control4 proxy reports fault and exposes a jammed condition for programming.

#### Scenario: Missing state
- **WHEN** a successful device read has no recognized lockState
- **THEN** the proxy reports unknown instead of inferring the bolt position from an earlier request.

### Requirement: Command confirmation
Command acceptance by the cloud SHALL be distinct from confirmed bolt state. After a lock or unlock request, the driver SHALL perform bounded state readback for up to 30 seconds and report confirmation, a fault, or an unconfirmed outcome without declaring success from HTTP acceptance alone.

#### Scenario: Accepted request never reaches the lock
- **WHEN** the cloud accepts an unlock request but subsequent reads do not confirm the requested state within 30 seconds
- **THEN** the command is reported as unconfirmed and the last observed state is retained with its freshness information.

### Requirement: Ordered and expiring commands
The driver SHALL serialize mutations per lock, retain at most the newest unsent explicit lock/unlock intent, and expire unsent intents 30 seconds after the user's request. It SHALL clear pending intents on restart, account change, sign-out, or lock removal.

#### Scenario: Connection recovers after intent expires
- **WHEN** an unlock request remains unsent for over 30 seconds and connectivity later recovers
- **THEN** the expired unlock is discarded and the lock does not execute it.

#### Scenario: Newer intent supersedes an unsent request
- **WHEN** Lock is requested while an earlier Unlock intent is still unsent
- **THEN** only the newer Lock intent remains eligible for transmission.

#### Scenario: New action follows an acknowledged write
- **WHEN** the previous write has a successful cloud acknowledgement and a newer explicit action is queued
- **THEN** the driver may cancel the previous command's confirmation reads and dispatch the newest action without waiting for that older state confirmation
- **AND** neither HTTP acknowledgement nor cached pre-write state confirms the new command, and late superseded reads cannot overwrite its state or outcome.

#### Scenario: Previous write has an uncertain outcome
- **WHEN** a newer action is requested after the previous write failed or timed out
- **THEN** the driver retains the previous write's bounded reconciliation barrier, honors rate limits, and expires the newer intent if it remains unsent for 30 seconds.

### Requirement: Uncertain writes and stale responses
The driver SHALL read current state after an uncertain write outcome instead of automatically replaying the mutation. A response issued before a newer dispatched write or account lifecycle change SHALL not overwrite the newer device state.

#### Scenario: Timeout after unlock transmission
- **WHEN** an unlock request times out after it might have reached the cloud
- **THEN** the driver queries state and reports the observed outcome without blindly retrying the unlock.

### Requirement: Availability and battery information
The companion SHALL expose online status, last successful update, battery percentage when provided, low-battery state when provided, and command outcome for Composer programming. Unbinding, explicit device disconnection, account unavailability, or stale account data SHALL make the companion offline.

#### Scenario: Fresh battery information received
- **WHEN** a supported lock reports a valid battery percentage and low-battery indication
- **THEN** the companion updates those values independently of its locked state.

#### Scenario: Cloud reports device disconnected
- **WHEN** a successful account read reports the lock disconnected
- **THEN** its companion reports offline and rejects new mutations until fresh connected data is available.

### Requirement: Capabilities reflect implemented behavior
The companion SHALL advertise only implemented lock capabilities. It SHALL not present PIN management, schedules, history, or door-open status unless separately implemented and supported by the device.

#### Scenario: First-version installation
- **WHEN** the initial driver bundle is installed
- **THEN** Control4 presents lock control and implemented telemetry without unsupported code-management or door-position controls.

### Requirement: Local diagnostics and Composer programming
The companion SHALL provide stable Composer events and conditions for implemented state and command outcomes. Initial synchronization, duplicate observations, and identity changes SHALL not fabricate physical movement events. Both drivers SHALL expose local diagnostics that exclude credentials, cloud lock identifiers, account scopes, raw responses, and unvalidated text fields.

#### Scenario: Driver reloads with a previously locked device
- **WHEN** the first post-reload snapshot reports locked
- **THEN** the Locked condition becomes available without firing a Locked movement event or a prior Command Confirmed event.

#### Scenario: Diagnostics requested with logging Off
- **WHEN** the installer runs Diagnostics Snapshot
- **THEN** the Lua tab receives an allowlisted local report even with Log Mode Off and no data is uploaded to an external diagnostics service.
