# Core

This document covers the pure Swift Hangul input-method core in `hisle-core/`.
Read it before changing Hangul composition, Cole Sebeol behavior, key layout
data, Unicode Hangul handling, or core tests.

## Scope

- `hisle-core/` is a pure Swift library subpackage.
- Keep testable Hangul composition behavior in `hisle-core/` where possible.
- Keep InputMethodKit-specific behavior in `hisle/InputMethod/`; do not move
  macOS client/session concerns into the core.
- Read `docs/terminology.md` before changing key layout, Hangul composition,
  modifier-key behavior, or implementation notes that mention representative
  keys.

## Commands

Preferred core contract/spec check:

```sh
nix develop .#core --command -- make core-spec-check
```

Core build:

```sh
nix develop .#core --command -- swift build --quiet --package-path hisle-core
```

Use the pinned Swift from `flake.nix` for Swift and SwiftPM work. Always run
core Swift commands through `nix develop .#core --command -- swift ...`; do not
call `/usr/bin/swift` directly.

If the pinned Swift toolchain cannot run a Swift command, report that toolchain
limitation instead of silently falling back to `/usr/bin/swift`. With the
current flake lock, `swift build --package-path hisle-core` works, but
`swift test --package-path hisle-core` is blocked because nixpkgs SwiftPM
disables the XCTest runner on macOS and this Swift does not provide the
`Testing` module. Use `nix develop .#core --command -- make core-spec-check`
for the XCTest-free Cole Sebeol core contract/spec check.

Core SwiftPM checks must run from the `core` shell and must not depend on a
host Xcode developer directory. Do not set `DEVELOPER_DIR` for core-only work
or reroute core commands to `/usr/bin/swift`.

## References

- Use `../libhangul` (https://github.com/libhangul/libhangul) as the reference
  for Unicode Hangul values, Sebeolsik layout data, and behavior comparison.
