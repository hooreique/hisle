# Packaging

This document covers local DMG packaging, Developer ID signing, notarization,
and stapling. Read it before changing `tools/package_dmg.nu`,
`tools/notary.nu`, release signing settings, or release workflows that call
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

## Release Workflow

Use the manual `Build DMG` GitHub Actions workflow to create a release
candidate. It builds, signs, notarizes, staples, validates, and uploads one DMG
artifact. This workflow does not create a tag or GitHub Release.

Inspect the candidate DMG manually before promotion. The build summary prints a
single-line Nix attr set containing the app version and the final stapled DMG's
Nix SRI SHA-256 hash:

```nix
{version="0.1.6";dmgHash="sha256-...";}
```

Paste that attr set into the `build-info.nix` input for the manual `Package
Release` workflow. The same hash can be
recomputed from a downloaded candidate with:

```sh
nix hash file --type sha256 --sri hisle-VERSION.dmg
```

Promote the latest successful `Build DMG` run on `main` by running
`Package Release` with the approved `build-info.nix` attr set. The package workflow
writes that input to `build-info.nix` with the standard generated-file comment,
evaluates the file with Nix to read the approved version and hash, downloads
that build's artifacts, requires exactly one DMG, verifies the filename,
recomputes the DMG hash, extracts the app with `undmg`, verifies the app
version, tags the package metadata commit, and creates the draft GitHub Release
with the approved DMG attached. `package.nix` imports `build-info.nix` at
evaluation time, so normal release promotion does not rewrite `package.nix`.

Build local DMG artifacts with `make dmg`. By default this creates a Debug
development DMG under `build/dist/`. Use `CONFIGURATION=Release` for release
packaging. The DMG is the intended first binary distribution container, while
notarization and stapling remain release-only steps that require Developer ID
credentials.

Release DMGs are intentionally compressed UDZO images with an HFS+ internal
filesystem so `pkgs.undmg` can extract them in Nix-based validation. Do not
switch the release image back to an implicit filesystem without revalidating
`undmg` compatibility.

Release packaging workflows run on `macos-26` so GitHub Actions uses Xcode 26
for asset catalog compilation. Keep release packaging on Xcode 26 or newer
unless the app icon output is revalidated; the app icon source is an
`AppIcon.icon` document and older Xcode defaults can produce a different
`AppIcon.icns` even when the icon image assets themselves are unchanged.

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
