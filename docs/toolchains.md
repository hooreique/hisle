# Toolchains

This document covers Nix shells and packages, Xcode boundaries, local build
products, helper scripts, and version ownership. Read it before changing
`flake.nix`, `package.nix`, `Makefile`, build scripts in `tools/`, Xcode build
settings, or version declarations.

## Commands

Show command summary:

```sh
nix develop --command -- make help
```

Print active Xcode toolchain information:

```sh
nix develop --command -- make check-toolchain
```

This also prints `HISLE_DEV_SHELL`, the Xcode `swiftc` selected by `xcrun`,
and the first `swiftc` on `PATH`. In the app and browser shells, `swiftc` must
not resolve to the Nix Swift compiler.

Remove local build products:

```sh
nix develop --command -- make clean
```

Version ownership check:

```sh
nix develop --command -- make version-check
```

Lint Swift sources with SwiftLint:

```sh
nix develop --command -- make swiftlint
```

SwiftLint uses `.swiftlint.yml` and excludes generated SwiftPM build output
under `hisle-core/.build`.

Xcode-oriented dev shell check:

```sh
nix develop --command -- xcodebuild -version
```

Build the packaged release app from the pinned DMG:

```sh
nix build .#hisle
```

## Make Targets

Prefer the `make` targets for local build, install, uninstall, cleaning,
packaging, testing, and icon rendering. They are the stable developer entry
points, but they must be run from the owning Nix dev shell. The Makefile does
not call `nix develop` itself, and targets that require a specific shell fail
early when `HISLE_DEV_SHELL` does not match.

Use these shell routes:

| Area | Shell | Example |
| --- | --- | --- |
| `hisle` app, Xcode builds, install, packaging, GUI smoke tests | `default` | `nix develop --command -- make build` |
| `hisle-core` pure SwiftPM work | `core` | `nix develop .#core --command -- make core-spec-check` |
| Chrome/Playwright IME diagnostics and Atlassian Confluence live repros | `browser` | `nix develop .#browser --command -- make chrome-ime-repro` |
| Icon rendering | `icon` | `nix develop .#icon --command -- make icons` |

For interactive work, enter the owning shell once, such as `nix develop` or
`nix develop .#core`, then run bare `make` targets inside that shell. The
examples above use `nix develop ... --command -- make ...` for one-shot
commands and automation.

Keep helper scripts in Nushell and run them through the owning Nix dev shell.
Do not add cross-shell Make dependencies; run checks that belong to different
shells as separate commands.

Local app builds are written under `build/` with `SYMROOT`, not Xcode's default
DerivedData location.

## Known Xcode Warnings

Xcode-oriented targets may print warnings that are not `hisle` behavior
regressions. Treat these as known toolchain noise unless the build fails or the
warning text changes materially.

CoreSimulator version warnings can appear while building this macOS input method
target. The stale-service form includes messages such as:

```text
DVTErrorPresenter: Unable to load simulator devices.
CoreSimulator is out of date.
Simulator device support disabled.
```

This is usually local Xcode/CoreSimulator service state, not a `hisle` build
setting. If Xcode reports stale or out-of-date CoreSimulator services, first
run:

```sh
nix develop --command -- xcrun simctl list devices
```

Let the command finish even if it prints platform-key warnings. It may repair a
stale CoreSimulator service, then print `== Devices ==`. Rebuild after that
before treating the warning as a project issue. If the same out-of-date
CoreSimulator warning remains after this command, investigate the local
macOS/Xcode installation before changing project build settings.

Xcode 26.6 runs `ExtractAppIntentsMetadata` for Swift targets even though
`hisle` does not define App Intents and does not need Siri, Shortcuts,
Spotlight, widget, control, or Apple Intelligence actions. The warning commonly
looks like:

```text
Metadata extraction skipped. No AppIntents.framework dependency found.
```

Do not link `AppIntents.framework` only to silence this warning. That would add
an unused framework dependency to satisfy a build tool check, not to support an
actual product feature.

Dependency-free warning-removal attempts checked on 2026-06-28 with Xcode 26.6
did not produce a clean supported fix:

- `ENABLE_APP_INTENTS_METADATA_GENERATION=NO` and
  `ENABLE_APPINTENTS_METADATA_GENERATION=NO` did not stop metadata extraction.
- `LM_FILTER_WARNINGS=YES` passed `--quiet-warnings`, but the framework warning
  still printed.
- `LM_ENABLE_LINK_GENERATION=NO` passed `-d`, but replaced the warning with
  `Metadata extraction disabled by --disable`.
- `LM_COMPILE_TIME_EXTRACTION=NO` left the app target warning in place.
- `SWIFT_ENABLE_EMIT_CONST_VALUES=NO` added another metadata warning.
- Empty `SWIFT_EMIT_CONST_VALUE_PROTOCOLS` failed the build.
- The older `OTHER_SWIFT_FLAGS` workaround with
  `-Xfrontend -disable-autolink-framework -Xfrontend AppIntents` did not remove
  the warning in this Xcode version.

## Nix Shells

Each dev shell appends `/usr/bin:/bin` after the Nix paths so macOS system
tools remain available while still resolving Nix-provided tools first when
present. Each shell also sets
`NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING=1` to suppress the Nix cc-wrapper's
known multi-target warning without hiding Swift compiler diagnostics, and
`HISLE_DEV_SHELL` to its shell name.

The default shell is the app/Xcode shell. It includes Nushell, SwiftLint, and
`undmg`, and sets `/Applications/Xcode.app/Contents/Developer` as
`DEVELOPER_DIR` when that path exists. It intentionally does not include Nix
Swift or SwiftPM; app builds and GUI helper drivers use Xcode's Swift toolchain
through `xcodebuild` or `xcrun swiftc`. It also unsets Nix compiler and SDK
variables so Xcode tools do not accidentally see the Nix apple-sdk. Run
Xcode-oriented Make targets from this shell. In automation, prefer
`nix develop --command -- make build` over host-shell `make build` or one-off
`DEVELOPER_DIR=... make build` invocations. If a host-shell `make build` fails
because `xcode-select` points at Command Line Tools, rerun the command through
`nix develop` before reporting a build issue.

The `core` shell is for pure `hisle-core` SwiftPM work. It includes Nushell,
Swift, and SwiftPM, and does not set `DEVELOPER_DIR`.

The `browser` shell is for Chrome IME diagnostics and Atlassian Confluence live
repros. It includes the default app/Xcode tools plus Node.js/npm so
`tools/chrome_ime_repro.nu` and `tools/atlassian_confluence_repro.nu` can
install and run their Playwright observers. It also intentionally avoids Nix
Swift because the browser HID drivers import macOS frameworks and are compiled
with Xcode's `xcrun swiftc`.

The `icon` shell is for icon rendering. It includes Nushell, `resvg`, and
ImageMagick.

The debug install helper sets `DEVELOPER_DIR` to
`/Applications/Xcode.app/Contents/Developer` when that path exists. Override
that with `XCODE_DEVELOPER_DIR` when a different Xcode is required.

Xcode-oriented Make targets call `/usr/bin/xcodebuild` through an environment
scrubber that clears Nix compiler, linker, and SDK variables such as `CC`,
`CXX`, `LD`, and `SDKROOT`. Preserve that boundary when changing Xcode build
helpers so Xcode does not inherit Nix toolchain settings.

## Nix Package

`package.nix` packages the signed release DMG exposed as
`packages.aarch64-darwin.hisle`, `packages.aarch64-darwin.default`, and through
the `overlay` output as `pkgs.hisle`.
It imports the pinned release version and DMG file hash from `build-info.nix`,
extracts the matching GitHub release asset with `undmg`, and installs
`hisle.app` under `$out/Library/Input Methods/` so the package mirrors the
macOS input method install location. Do not enable fixup phases that rewrite the
bundled app or helper binaries, because that would invalidate release code
signatures.

`home-manager.nix` is exposed as the `homeManagerModule` output. When
`programs.hisle.enable` is true, it manages
`~/Library/Input Methods/hisle.app` by copying the app bundle from
`programs.hisle.package`, defaulting that package to `pkgs.hisle`. Keep this as
a real copy rather than a `home.file` symlink because macOS input methods are
not reliably discovered from symlinked app bundles. The copy step follows Home
Manager's Darwin app-copying policy: use `rsync`, preserve app-internal
relative links, convert unsafe store links into real files, delete stale files,
make the copied tree writable, and avoid preserving Nix store mtimes.
App Management permission failures are left to the `rm` or `rsync` activation
step that triggered them. When `programs.hisle.enable` is false on Darwin, the
module removes
`~/Library/Input Methods/hisle.app`.

`build-info.nix` is updated during release promotion by the `Package Release`
workflow, not during DMG candidate builds. Release promotion should update only
that file's `version` and `dmgHash` fields after verifying the approved
candidate artifact. `package.nix` should not be edited for ordinary release
metadata bumps.

## Versions

Keep app and core versions independent. The app distribution version lives in
`hisle/Config/HisleVersion.xcconfig` as `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION`; the `hisle-core` library version lives in
`hisle-core/Sources/HisleCore/HisleCoreVersion.swift` as `HisleCore.version`.
Do not require these versions to match.

During bug-fix investigation, use `CURRENT_PROJECT_VERSION` as the runtime
identity marker for installed debug app binaries. Do not bump
`MARKETING_VERSION` for each investigation build. See `docs/bugfixes.md` for
the bug-fix workflow.

Use `nix develop --command -- make version-check` after version ownership
changes.

## References

- Use `../ghostty` (https://github.com/ghostty-org/ghostty) as the reference
  for strong Nix usage that still accounts for Apple tools.
