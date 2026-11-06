# Tasks

Implementation is in progress. Complete groups in order; group 3 is a hardware gate before lock-command implementation. Specs define acceptance behavior and design.md records the source references and technical choices. Hardware observations are recorded in docs/hardware-validation.md.

## 1. Project foundation

- [x] 1.1 Record the target controller model/OS, lock identifiers/firmware, and development-project access in a hardware validation record; verify that the record identifies an available controller and at least one supported Encode-family lock.
- [x] 1.2 Select and pin a reviewed Finite Labs template tag, render with `bitn crypto` into staging, and integrate it while preserving OpenSpec and generated skills; verify the Copier answers and a before/after inventory of planning files.
- [x] 1.3 Configure the OSS build, project identity, disabled external diagnostics, attribution, and upstream notices; verify output contains the project's own metadata and no Finite Labs service credentials or licensing requirement.
- [x] 1.4 Provision the template toolchain and create account/lock packaging skeletons plus Schlage-local test fixtures; verify baseline shared tests and an OSS build pass, and document the reproducible local commands.

## 2. Cognito protocol and account session

- [x] 2.1 Pin pycognito and Schlage reference revisions and derive synthetic Cognito golden vectors; verify fixtures cover leading-zero/sign padding, canonical username, SHA-256/HKDF, secret hash, signature, and UTC timestamp without real account data.
- [x] 2.2 Implement the Cognito SRP calculation adapter with verified secure randomness and accelerated big numbers; verify the Lua outputs match the independent vectors and unusable entropy/acceleration is reported without an insecure fallback.
- [x] 2.3 Implement asynchronous Cognito login, challenge parsing, token expiry, and refresh; verify mocked valid login, invalid credentials, unsupported challenge, transient error, revoked token, concurrent renewal, and omitted replacement refresh-token cases.
- [x] 2.4 Implement encrypted session/credential persistence, masked entry with plaintext clearing, explicit sign-in/sign-out, and lifecycle generations; verify restart recovery, credential replacement, late callbacks, destruction, and sign-out leave no old session active.
- [x] 2.5 Add Schlage-specific secret filtering and control low-level HTTP/debug tracing; verify sentinel credentials, SRP private values, CAT/SAT, identity headers, PINs, and nested/serialized payloads never appear at the highest supported log level. Document sign-in and reauthentication behavior.
- [x] 2.6 Implement a read-only authenticated REST discovery request and normalized error handling; verify sanitized fixtures for valid device lists, malformed JSON, 401, 429, transport errors, and empty accounts.

## 3. Native authentication hardware gate

- [x] 3.1 Install the read-only account build in the development Control4 project; verify TLS trust, secure randomness, OpenSSL acceleration, synchronous crypto work within the 250 ms engineering budget, and another driver's timer responsiveness, recording measurements.
- [x] 3.2 Sign in to the real Schlage account and list locks directly from the controller; verify returned cloud IDs/model types against the Schlage app and save only sanitized observations in the validation record.
- [x] 3.3 Exercise real token renewal and controller restart recovery, then inspect logs and a project export for plaintext secrets; verify no credential reentry is needed with a valid refresh token and no runtime bridge/authentication server is involved.

Do not mark this group complete from mocks. If a hardware prerequisite fails, record the measured issue and resolve it before group 4.

## 4. Discovery, bindings, and polling

- [x] 4.1 Implement supported device-type checks and normalized state/telemetry models keyed by cloud device ID; verify every specified lock state, missing telemetry, unknown types, and disconnected devices against table-driven fixtures.
- [x] 4.2 Implement stable dynamic bindings and companion Properties dropdowns for account and physical-lock selection; support multiple companions in any room and verify repeat selection, rename/removal/reappearance, restart, account changes, and unrelated project devices cause no duplicate or cross-account binding.
- [x] 4.3 Implement the account polling lifecycle with configured intervals, one scheduled poll in flight, retry/backoff, Retry-After handling, and 120-second staleness; verify these timings with simulated time and distinguish retrieval failures from valid empty results.
- [x] 4.4 Implement companion startup/refresh/disconnect handoff with normalized public snapshots; verify child restart, rebind/unbind, account restart, and out-of-order callbacks restore correct online status without transmitting secrets. Document companion selection and polling settings.

## 5. Native lock control and confirmation

- [x] 5.1 Adapt ESPHome's standard lock proxy handlers and implement explicit Schlage Wi-Fi lock/unlock requests; verify proxy dispatch, device-ID routing, request method/body, known-state toggle, and rejection of unknown/offline/unsupported targets.
- [x] 5.2 Implement per-lock serialization, newest-unsent-intent coalescing, 30-second expiry, and lifecycle cancellation; verify rapid opposite commands, delayed authentication, disconnect/reconnect, removal, and restart never execute a stale queued unlock.
- [x] 5.3 Implement bounded reported-state readback and per-device response revisions; verify confirmation, delayed state, jam, missing state, uncertain timeout, 401, 429, deadline expiry, and stale pre-write reads without automatic mutation replay.
- [x] 5.4 Publish independent online/bolt/fault/battery/outcome variables and proxy notifications, with only implemented XML capabilities; verify state-mapping scenarios, telemetry-only changes, disconnect with unchanged bolt position, and Navigator/Composer presentation. Document command outcomes and deferred features.

## 6. Integrated validation and installable delivery

- [ ] 6.1 Exercise native lock/unlock, manual thumbturn/app changes, battery reporting, multiple locks when available, and a safely reproducible jam or documented fault fixture; verify observed behavior against the specs and record the tested model/firmware combinations.
- [ ] 6.2 Exercise controller reboot, network outage, Schlage rejection, stale state, and recovery end to end; verify existing project responsiveness, bounded request volume, accurate offline reporting, and absence of delayed unlocks or leaked credentials.
- [x] 6.3 Run project tests, formatting/static checks, build, and packaging; verify the installable account/lock `.c4z` bundle and generated documentation load in Composer and list only the hardware/OS combinations actually validated.
- [ ] 6.4 Rehearse commissioning and rollback using the delivered documentation in the development project; verify the existing HA bridge can remain available during testing and original bindings can be restored without lock reset or re-enrollment.

## 7. GitHub release updater (requested during commissioning)

- [x] 7.1 Integrate the template updater and shared settings with one account coordinator, bounded timers, idle-command checks, manual action, persistent status, and lifecycle cleanup; verify mocked channel, failure, duplicate-flight, and settings synchronization scenarios.
- [x] 7.2 Add increasing same-day release revisions and tag/package consistency checks while retaining template-managed tools; verify local and CI version selection and invalid tags.
- [x] 7.3 Run tests, build and package checks; copy the bootstrap packages to OneDrive and document update setup plus the assessment of other useful template features.
- [x] 7.4 Publish a reviewable GitHub prerelease and verify the update source; record actual controller automatic-update validation separately from local checks.

## 8. Useful template integrations (requested during review)

- [x] 8.1 Add local allowlisted diagnostic actions to both drivers; verify sentinel credentials, cloud IDs, malformed values, and nested payloads are absent.
- [x] 8.2 Integrate stable programming events and conditions for availability, reported bolt/fault, battery, and command outcomes; verify initial synchronization, repeats, reload, and reassignment do not fabricate movement events.
- [x] 8.3 Add independent Composer icons and document the option-by-option template assessment, commissioning controls, and remaining live acceptance checks; verify packaged assets and documentation.

## Workflow follow-up

- Review the completed implementation and live validation record before production cutover or publication.
- Archive this OpenSpec change only after its implementation tasks and acceptance gates are complete.
