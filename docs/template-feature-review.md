# Template integration review

Reviewed against the pinned Finite Labs template v0.9.74. This is an OSS driver;
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
| Minimum OS / crypto checks | Existing minimum OS 3.4.1 declaration and native acceleration/secure randomness checks retained. CORE 1/3.4.3 is the observed test context; CORE 5 remains untested. |
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
commits or template updates. Development releases remain prereleases until
hardware acceptance is complete. A public release source and actual controller
download/install still need verification beyond the mocked tests.
