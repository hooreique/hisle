# Toolchains

This document covers Nix shells, Xcode boundaries, local build products, helper
scripts, and version ownership. Read it before changing `flake.nix`, `Makefile`,
build scripts in `tools/`, Xcode build settings, or version declarations.

## Commands

Show command summary:

```sh
make help
```

Print active Xcode toolchain information:

```sh
nix develop .#xcode-work --command -- make check-toolchain
```

Remove local build products:

```sh
make clean
```

Version ownership check:

```sh
make version-check
```

Xcode-oriented dev shell check:

```sh
nix develop .#xcode-work --command -- xcodebuild -version
```

## Make Targets

Prefer the `make` targets for local build, install, uninstall, cleaning,
packaging, testing, and icon rendering. They are the stable developer entry
points.

Keep helper scripts in Nushell and run them through the Nix dev shell.

Local app builds are written under `build/` with `SYMROOT`, not Xcode's default
DerivedData location.

## Nix Shells

The default Nix dev shell appends `/usr/bin:/bin` after the Nix paths so SwiftPM
can find macOS's `codesign` during its debug executable signing step while still
resolving `swift` from Nix first. It also sets
`NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING=1` to suppress the Nix cc-wrapper's
known multi-target warning without hiding Swift compiler diagnostics.

Use the `xcode-work` Nix shell for Xcode-oriented commands that should see
`/Applications/Xcode.app/Contents/Developer` as `DEVELOPER_DIR`.

Run Xcode-oriented Make targets from the `xcode-work` shell. In automation,
prefer `nix develop .#xcode-work --command -- make build` over host-shell
`make build` or one-off `DEVELOPER_DIR=... make build` invocations. If a
host-shell `make build` fails because `xcode-select` points at Command Line
Tools, rerun the command through `xcode-work` before reporting a build issue.

The debug install helper sets `DEVELOPER_DIR` to
`/Applications/Xcode.app/Contents/Developer` when that path exists. Override
that with `XCODE_DEVELOPER_DIR` when a different Xcode is required.

Xcode-oriented Make targets call `/usr/bin/xcodebuild` through an environment
scrubber that clears Nix compiler, linker, and SDK variables such as `CC`,
`CXX`, `LD`, and `SDKROOT`. Preserve that boundary when changing Xcode build
helpers so Xcode does not inherit Nix toolchain settings.

## Versions

Keep app and core versions independent. The app distribution version lives in
`hisle/Config/HisleVersion.xcconfig` as `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION`; the `hisle-core` library version lives in
`hisle-core/Sources/HisleCore/HisleCoreVersion.swift` as `HisleCore.version`.
Do not require these versions to match. Use `make version-check` after version
ownership changes.

## References

- Use `../ghostty` (https://github.com/ghostty-org/ghostty) as the reference
  for strong Nix usage that still accounts for Apple tools.
