# Template integration review

Reviewed against the pinned Finite Labs template v0.9.80. This is an OSS driver;
template source updates remain explicit Copier updates reviewed in this repo.

| Template feature | Decision for this driver |
| --- | --- |
| GitHub Releases updater | Included. One account coordinates the installed account/lock packages, companions first and its own package last. Shared On/Off and Stable/Prerelease controls; manual check and lasting status. |
| Shared update settings / generated driver filename list | Included. New instances synchronize with the existing account and setting changes do not echo indefinitely. |
| Build, test, formatting, packaging and release workflows | Included. Tag and package versions must match; YYYYMMDDRR revisions support successive releases on one date. CI rejects version regression/reuse. |
| Async HTTP / deferred operations | Already used. Schlage requests use a quiet protocol adapter and preserve strict JSON decoding. No raw authentication trace is enabled. |
| Encrypted persistence | Already used for credentials/session. Public lock selection is separate; unchanged identities are not rewritten per snapshot. |
| Dynamic bindings | Already used for stable account/lock selection and automatic connection. Generic Door Lock relay binding remains a separate Navigator step. |
| Logging and redaction | Already used, with three-hour logging shutoff and safe command timing logs. |
| Local diagnostics | Included as Diagnostics Snapshot on both drivers, even with Log Mode Off. Explicit allowlist plus template redactor; no lock IDs, scope hashes, user-defined names, credentials or raw responses. No upload. |
| Events and conditionals | Included through the template's stable-ID helpers. Online/offline, locked/unlocked/jammed, low battery, command confirmed/failed events; online/locked/unlocked/jammed/low-battery conditions. Initial sync and duplicate snapshots do not claim movement. |
| Driver icons | Included for account and companion in Composer. Original project artwork; generic Door Lock retains its standard native Navigator icon. Source generator is tools/schlage_icons.py. |
| Minimum OS / crypto checks | Minimum OS 3.4.1 declaration and native acceleration/secure randomness checks retained. CORE 1/3.4.3 and CORE 5/4.3 have user-reported live validation; coverage is recorded in hardware-validation.md. |
| GitHub repository conventions | Apply CI/release workflows, description, squash merges, branch protection/admin bypass, and security alerts where supported. Review new template versions rather than automatically importing them. |
| Optional cloud diagnostics | Remain disabled, preserving the selected configuration. The template service requires DriverCentral and external service credentials; local diagnostics meet this project's current needs. |
| DriverCentral licensing / support-code gates | Excluded from the OSS runtime. No commercial service credentials or support-code secret are needed. |
| OAuth / protobuf / Noise / BTHome / BLE bundles | Excluded: Schlage uses Cognito SRP and HTTPS; these transports do not implement the requested Wi-Fi integration. |
| LRU / generic value helpers | Available as dependencies when needed; no extra cache or coercion layer is added without a concrete use. |
| Variant expansion | Available but unused: per-lock dropdown selection supports the known models without packaging duplicate model drivers. |
| Marketing card/photo tooling | Available in the source template; not part of runtime or commissioning. No third-party branding is used for the project icons. |
| Stale-issue automation | Remains disabled for the small commissioning-stage project. |

Runtime update checks begin after 60 seconds and repeat every six hours. A
pending command delays starting a check; updates can reload drivers, so use
Automatic Updates Off during controlled testing if needed. A manual check is
still available. Channels select published GitHub releases, never arbitrary
commits or template updates. Version 2026110608 is the initial stable release
requested by the user, with outage/recovery testing explicitly deferred. The
public release API and both download assets are verified, including template
release selection against live metadata. Automatic controller download/install
was observed with the earlier prereleases. OAuth through Allegion's partner API
is a separate potential integration and is on hold pending provider replies.

## v0.9.74 to v0.9.80 maintenance

Copier updated the pinned source to
`2da61295cab1af22b89d18a2dad36c94a4e3f00f` without conflicts. The existing
OSS-only build, increasing version/tag checks, release workflows, and optional
module choices remain in place. Expressions, external cloud diagnostics, and
OAuth are still excluded.

- Included the connection rename fix, optional HTTP response/header/redirect
  controls, variable/property separation, and build-aware test fixtures.
- Updated bitn and crypto bundles remove upstream self-tests and benchmarks
  from runtime packages. Runtime OpenSSL checks and project Cognito/SRP golden
  vectors remain covered by the driver tests.
- Adapted the drivers to disable raw debug dumps after the new logger's settings
  are applied. Structured Trace/Ultra remains available; shared libraries are
  unmodified from the Copier result.
- The template's DriverCentral image renderer updates as managed tooling, but
  no DriverCentral runtime or optional diagnostics service is enabled.

The first source run reproduced the logging incompatibility in two existing
privacy assertions. After the driver adaptation and additional mode/level
checks, 58 Lua suites / 2,521 assertions and 53 Python tests passed. These local
results do not complete deferred hardware acceptance.
