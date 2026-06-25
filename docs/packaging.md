# Packaging

This document covers local DMG packaging, Developer ID signing, notarization,
and stapling. Read it before changing `tools/package_dmg.nu`,
`tools/notary.nu`, release signing settings, or the release workflow that calls
these tools.

## Commands

Build and package a local DMG artifact:

```sh
nix develop .#xcode-work --command -- make dmg
```

Direct DMG package script:

```sh
nix develop --command -- nu tools/package_dmg.nu
```

Direct notarization and staple script for a signed DMG:

```sh
nix develop --command -- nu tools/notary.nu
```

Build local DMG artifacts with `make dmg`. By default this creates a Debug
development DMG under `build/dist/`. Use `CONFIGURATION=Release` for release
packaging. The DMG is the intended first binary distribution container, while
notarization and stapling remain release-only steps that require Developer ID
credentials.

For Developer ID packaging, pass Xcode signing overrides such as
`CODE_SIGN_STYLE`, `CODE_SIGN_IDENTITY`, and `DEVELOPMENT_TEAM`; pass
`DMG_SIGN_IDENTITY` to sign the disk image itself. Release Developer ID
packaging must sign the app and helper with secure timestamps; the package
script adds `--timestamp --options runtime` and validates the timestamps before
creating the DMG.

## Notary Credentials

Keep local release credentials under ignored `local/`, not in the repository
root. `tools/notary.nu` reads notary credentials from environment variables
(`NOTARY_API_KEY_PATH`, `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID`) or from
one-value local files (`local/notary-api-key-path`,
`local/notary-api-key-id`, and `local/notary-api-issuer-id`), so CI can reuse
the same script without checking in local secrets.

The script stores the last local submission ID in
`local/current-notary-submission-id`.
