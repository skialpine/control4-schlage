# Local delivery policy

- Publish new driver releases as prereleases, never directly as Latest. Keep the
  last accepted stable release as Latest until the user confirms live testing of
  the new version. Passing local tests or CI is not live acceptance. Promote a
  release to stable/Latest only after that confirmation.

- Do not copy, place, or overwrite driver packages in the user's OneDrive
  `Documents/Control4/Drivers` directory. Composer manages that local driver
  database. Copying a release there externally made the local and controller
  versions appear equal while Composer still showed an older property layout.

- Deliver `.c4z` files, bundles, and documentation to the main OneDrive
  `Documents/Control4` folder only. Use GitHub Releases for controller updates.

- Let the user import or synchronize drivers through Composer. Do not work
  around a stale Composer definition by writing into its Drivers directory.

- Leave existing Drivers files in place unless the user explicitly requests a
  separate cleanup. This policy changes future delivery, not installed devices.
