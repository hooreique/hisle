# Agent Development Guide

## Documentation Boundaries

- `AGENTS.md` is for maintainers and coding agents. Keep project layout,
  commands, workflow rules, implementation references, and conventions here.
- `README.md` and `README.ko.md` are for people who want to use the input
  method. Keep them focused on what the program is, its current status, how to
  install it, how to select it as an input source, and how to remove it.
- Avoid unnecessary duplication between `AGENTS.md` and the README files. If a
  detail is only useful while changing the code, keep it out of the README. If a
  fact is useful to both users and maintainers, keep the README version brief
  and put the operational detail here.
- When adding new developer commands, conventions, or repository structure,
  update this file first. Update README files only when the user-facing behavior
  or installation/removal instructions change.

## Project Layout

- This repository contains the source code for the `hisle` input method
  (`이슬`).
- `hisle-core/` is a pure Swift library subpackage. It implements and tests the
  core Hangul input-method behavior.
- `hisle-cli/` contains the companion command-line helper that is bundled into
  `hisle.app/Contents/Helpers/hisle`.
- `hisle/App/` contains the app lifecycle and input-method server startup.
- `hisle/InputMethod/` contains the InputMethodKit controller and server code.
- `hisle/AppIcon.icon/` contains the Icon Composer app icon document used by
  modern macOS app icon rendering. Its foreground SVG is also the source for
  fallback app icon PNG slots.
- `hisle/Assets.xcassets/` contains the fallback app icon asset catalog rendered
  from `hisle/AppIcon.icon/Assets/HisleLogo.svg`.
- `hisle/Resources/` contains bundled input method icon resources.
- `hisle/Info.plist` contains input method metadata consumed by macOS.
- `tools/` contains local Nushell build/install helpers.
- `docs/` contains development notes.
- `docs/input-modes.md` specifies `hisle` input-mode behavior, including
  left/right Shift mode selection and the boundary between `hisle`, Colemak,
  and Cole Sebeol responsibilities.
- `docs/two-icons.md` explains the separate app icon and input source icon
  workflows. Read it before changing, regenerating, or deleting icon assets.
- `docs/testing.md` contains long-lived verification procedures, including the
  scripted GUI smoke test.
- `docs/terminology.md` defines project-specific terminology for key layouts,
  representative key notation, and underlying roman layout behavior.

## Commands

- Show command summary: `make help`
- Build the macOS input method app:
  `nix develop .#xcode-work --command -- make build`
- Build and package a local DMG artifact:
  `nix develop .#xcode-work --command -- make dmg`
- Debug install into `~/Library/Input Methods`: `make install-debug`
- Remove the local debug install: `make uninstall`
- Remove local build products: `make clean`
- Render icon assets: `make icons`
- Print active Xcode toolchain information:
  `nix develop .#xcode-work --command -- make check-toolchain`
- Core build:
  `nix develop --ignore-environment --command -- swift build --quiet --package-path hisle-core`
- Core contract/spec check: `make core-spec-check`
- Direct debug install script:
  `nix develop --command -- nu tools/install_debug.nu`
- Direct DMG package script:
  `nix develop --command -- nu tools/package_dmg.nu`
- Direct notarization and staple script for a signed DMG:
  `nix develop --command -- nu tools/notary.nu`
- Direct uninstall script: `nix develop --command -- nu tools/uninstall.nu`
- GUI smoke test:
  `make gui-smoke-test`
- Direct GUI smoke test driver, after a debug install:
  `nix develop --command -- nu tools/gui_smoke_test.nu`
- Chrome textarea IME reproduction tool:
  `make chrome-ime-repro`
- Direct Chrome textarea IME reproduction tool, after a debug install:
  `nix develop .#browser-work --command -- nu tools/chrome_ime_repro.nu`
- Enable debug-only IMK client range tracing for an installed Debug build:
  `defaults write hooreique.inputmethod.hisle traceClientRanges -bool YES`
- Disable debug-only IMK client range tracing:
  `defaults delete hooreique.inputmethod.hisle traceClientRanges`
- Installed companion CLI, after a debug install:
  `"$HOME/Library/Input Methods/hisle.app/Contents/Helpers/hisle"`
  Without options it prints `roman` or `hangul`; `--version` prints both the
  app version and `hisle-core` version.
- Direct icon render script:
  `nix develop .#icon-work --command -- nu tools/render_icons.nu`
- Xcode-oriented dev shell:
  `nix develop .#xcode-work --command -- xcodebuild -version`

## Workflow Rules

- Prefer the `make` targets for local build, install, uninstall, cleaning, and
  icon rendering. They are the stable developer entry points.
- This project expects Apple Xcode tools and Nix to be available. Use
  `nix develop .#xcode-work --command -- make check-toolchain` to print the
  active Xcode version, Swift compiler, and macOS SDK path.
- Do not run the input method directly from Xcode as the primary test path.
  Build it, install it into `~/Library/Input Methods`, then select it as an
  input source in System Settings.
- For core behavior changes, run `make core-spec-check`. For InputMethodKit,
  mode switching, modifier handling, shortcut forwarding, or bundled CLI
  behavior changes, run `make gui-smoke-test` when the local GUI prerequisites
  are available.
- For Chrome IME diagnostics, run `make chrome-ime-repro` when the local GUI
  prerequisites are available. The Chrome diagnostic runner types only through
  the Swift HID driver and real macOS input method path; Playwright is limited
  to launching or observing Chrome, DOM event capture, screenshots, and traces.
  Do not use Playwright keyboard APIs, `fill()`, or CDP text insertion for the
  actual typing under test.
- The Chrome diagnostic runner can also target `contenteditable` and WYSIWYG
  surfaces with `HISLE_CHROME_TARGET`; use `HISLE_CHROME_EDITOR_CHAOS` scenarios
  to reproduce idle-time editor DOM rewrites or focus churn. For cursor
  divergence experiments, prefer prefilled WYSIWYG runs with
  `HISLE_CHROME_INITIAL_TEXT`, `HISLE_CHROME_INITIAL_CARET`, and explicit move
  scenarios so the DOM selection and IMK marked range can be compared.
- For the GUI smoke test, follow `docs/testing.md`. The scripted driver opens a
  temporary file in Sublime Text, streams `hisle` logs, verifies mode changes
  through the bundled CLI, sends the documented GUI key sequence including
  Colemak-underlying Command+S saves, and checks saved file content.
- Chrome diagnostic artifacts are written under `build/chrome-ime/<run-id>/`.
  Each run expects Accessibility permission for the terminal process, an
  installed Chrome or `CHROME_PATH`, and a clean per-run Chrome profile managed
  by the observer sidecar.
- Debug builds can opt into noisy IMK client range traces with the
  `traceClientRanges` defaults key or `HISLE_TRACE_CLIENT_RANGES=1`. Release
  builds must not emit these traces; keep any Release logging limited to sparse
  lifecycle or unexpected fallback events.
- Local app builds are written under `build/` with `SYMROOT`, not Xcode's
  default DerivedData location.
- Use the pinned Swift from `flake.nix` for Swift and SwiftPM work. Always run
  Swift commands through `nix develop --ignore-environment --command -- swift ...`,
  and do not call `/usr/bin/swift` directly.
- The default Nix dev shell appends `/usr/bin:/bin` after the Nix paths so
  SwiftPM can find macOS's `codesign` during its debug executable signing step
  while still resolving `swift` from Nix first. It also sets
  `NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING=1` to suppress the Nix cc-wrapper's
  known multi-target warning without hiding Swift compiler diagnostics.
- Core SwiftPM checks must not depend on a host Xcode or Command Line Tools
  developer directory. In the default Nix shell, `DEVELOPER_DIR` and `SDKROOT` are
  expected to point into the Nix store Apple SDK, and `xcrun` is expected to be
  the Nix-provided `xcbuild` shim.
- Use the `xcode-work` Nix shell for Xcode-oriented commands that should see
  `/Applications/Xcode.app/Contents/Developer` as `DEVELOPER_DIR`.
- Run Xcode-oriented Make targets from the `xcode-work` shell. In automation,
  prefer `nix develop .#xcode-work --command -- make build` over host-shell
  `make build` or one-off `DEVELOPER_DIR=... make build` invocations. If a
  host-shell `make build` fails because `xcode-select` points at Command Line
  Tools, rerun the command through `xcode-work` before reporting a build issue.
- Build local DMG artifacts with `make dmg`. By default this creates a Debug
  development DMG under `build/dist/`; use `CONFIGURATION=Release` for release
  packaging. The DMG is the intended first binary distribution container, while
  notarization and stapling remain release-only steps that require Developer ID
  credentials. For Developer ID packaging, pass Xcode signing overrides such as
  `CODE_SIGN_STYLE`, `CODE_SIGN_IDENTITY`, and `DEVELOPMENT_TEAM`; pass
  `DMG_SIGN_IDENTITY` to sign the disk image itself.
- Keep local release credentials under ignored `local/`, not in the repository
  root. `tools/notary.nu` reads notary credentials from environment variables
  (`NOTARY_API_KEY_PATH`, `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID`) or from
  one-value local files (`local/notary-api-key-path`,
  `local/notary-api-key-id`, and `local/notary-api-issuer-id`), so CI can reuse
  the same script without checking in local secrets. The script stores the last
  local submission ID in `local/current-notary-submission-id`.
- Xcode-oriented Make targets call `/usr/bin/xcodebuild` through an environment
  scrubber that clears Nix compiler, linker, and SDK variables such as `CC`,
  `CXX`, `LD`, and `SDKROOT`. Preserve that boundary when changing Xcode build
  helpers so Xcode does not inherit Nix toolchain settings.
- If the pinned Swift toolchain cannot run a Swift command, report that
  toolchain limitation instead of silently falling back to `/usr/bin/swift`.
  With the current flake lock, `swift build --package-path hisle-core` works,
  but `swift test --package-path hisle-core` is blocked because nixpkgs SwiftPM
  disables the XCTest runner on macOS and this Swift does not provide the
  `Testing` module. Use `make core-spec-check` for the XCTest-free Cole Sebeol
  core contract/spec check.
- Keep helper scripts in Nushell and run them through the Nix dev shell.
- When changing `hisle-cli`, update the README CLI section and the GUI smoke
  test expectations if the command-line contract changes. The bundled helper's
  no-option output is part of the smoke test.
- The debug install helper sets `DEVELOPER_DIR` to
  `/Applications/Xcode.app/Contents/Developer` when that path exists. Override
  that with `XCODE_DEVELOPER_DIR` when a different Xcode is required.
- Icon rendering uses the `icon-work` Nix shell with `resvg` and ImageMagick.
  Read `docs/two-icons.md` before changing, regenerating, or deleting icon
  assets; the app icon and input source icon use different source files and
  consumers. Input source icons are rendered from
  `tools/icons/HisleInputSource.svg` into TIFF fallback files and
  `HisleInputSource@2x.pdf` under `hisle/Resources/`. The visible input mode
  points `TISIconLabels.CustomIcon` at the PDF so modern macOS input menus can
  use the custom icon path, while the TIFF keys remain for legacy TIS callers.
  Keep the top-level `TISInputSourceID` as the parent input method ID
  (`hooreique.inputmethod.hisle`) and the visible mode ID as
  `hooreique.inputmethod.hisle.main`; using the same ID for both creates
  duplicate TIS entries.

## Terminology

- Read `docs/terminology.md` when working on key layout, Hangul composition, or
  modifier-key behavior.
- Read `docs/input-modes.md` when working on input-mode state, left/right Shift
  handling, or the boundary between Roman mode and Hangul mode.
- Use the terminology from `docs/terminology.md` in conversations and
  implementation notes. In particular, use `대표 글쇠` for physical key labels
  based on standard US Qwerty, and do not translate `underlying roman layout`;
  keep that exact English phrase.

## Implementation Notes

- Keep the current public input source focused on `hisle`. Add other
  visible modes only after their user-facing behavior is specified.
- The reference repository paths below are defaults relative to this
  repository. Developer environments may use different paths or may not have
  these repositories at all. If a default path does not exist, check
  `AGENTS.local.md` for local reference paths; that file is optional and may
  not be present.
- Use `../gureum` (https://github.com/gureum/gureum) as the reference for app
  implementation and InputMethodKit behavior.
- Use `../ghostty` (https://github.com/ghostty-org/ghostty) as the reference for
  clear project layout and lightweight developer commands.
- Use `../libhangul` (https://github.com/libhangul/libhangul) as the reference
  for Unicode Hangul values, Sebeolsik layout data, and behavior comparison.
- Keep InputMethodKit-specific code in `hisle/InputMethod/` thin. Put testable
  Hangul composition behavior in `hisle-core/` where possible.
- Treat left Shift single tap as Roman mode selection and right Shift single
  tap as Hangul mode selection, as specified in `docs/input-modes.md`.
- The current visible input source is `hisle`. It starts in Roman mode with
  Colemak output, uses Cole Sebeol in Hangul mode, and leaves command/control
  shortcuts to the host app after flushing active composition.
