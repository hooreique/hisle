# Maintenance Guide

## Local Overrides

- `AGENTS.local.md`, when present, is the higher-priority local override for
  this guide.

## Documentation Boundaries

- `AGENTS.md` is for maintainers and coding agents. Keep only rules that apply
  to every change, the repository map, and routing to focused development docs
  here.
- `README.md` is the Korean-language project front page. Keep it focused on
  the logo, what `hisle` is, why it exists, its defining input policies, and
  the personal-project direction and contribution stance.
- Do not let `AGENTS.md` become user documentation, and do not let `README.md`
  become maintainer runbooks. If a detail is only useful while changing the
  code, keep it out of `README.md`. If a fact is useful to both users and
  maintainers, keep the README version brief and put operational detail in the
  appropriate `docs/*` file.
- Keep `docs/*` files separated by ownership area. Prefer linking to the owning
  document over duplicating procedures, command explanations, or policy text in
  several places.
- When behavior, commands, project structure, workflow rules, installation,
  packaging, or removal steps change, update the owning documentation in the
  same change. Update `README.md` only when a change belongs in the public
  project overview, motivation, defining feature summary, or contribution
  stance.

## Project Map

- `hisle-core/` is the pure Swift library subpackage for core Hangul input
  behavior.
- `hisle-cli/` contains the companion command-line helper bundled into
  `hisle.app/Contents/Helpers/hisle`.
- `hisle/App/` contains the app lifecycle and input-method server startup.
- `hisle/InputMethod/` contains the InputMethodKit controller and server code.
- `hisle/Config/` contains Xcode configuration files such as the app
  distribution version.
- `hisle/AppIcon.icon/`, `hisle/Assets.xcassets/`, `hisle/Resources/`, and
  `tools/icons/` contain app and input-method icon sources and outputs.
- `hisle/Info.plist` contains input method metadata consumed by macOS.
- `flake.nix` and `package.nix` contain Nix shells and the release DMG package.
- `tools/` contains local Nushell build, install, package, test, and icon
  helpers.
- `.github/workflows/build.yaml` builds signed, notarized DMG candidates.
- `.github/workflows/package.yaml` promotes an approved DMG candidate into
  `package.nix`, a version tag, and a draft GitHub Release.
- `bugfix/` contains per-bug investigation notes and status records.
- `docs/` contains focused maintainer notes. Keep each topic in its owning
  document.
- `docs/getting-started.md` is the low-profile user-facing exception for
  install, prerequisites, first-run, and removal notes.

## Read Before Changing

- Bug fixes or bug-specific investigation records: read `docs/bugfixes.md`,
  then read the owning area document for the expected code change.
- Core Hangul behavior, Cole Sebeol, Unicode Hangul values, key layout data, or
  `hisle-core/`: read `docs/core.md` and `docs/terminology.md`.
- Input modes, left/right Shift behavior, Escape behavior, shortcut forwarding,
  host action keys, or Roman/Hangul boundaries: read `docs/input-modes.md` and
  `docs/macos-imk.md`.
- InputMethodKit, input source metadata, app lifecycle, or `hisle-cli/`: read
  `docs/macos-imk.md`.
- Installation, getting started, prerequisites, or removal instructions: read
  `docs/getting-started.md`, then route command mechanics to
  `docs/toolchains.md`, InputMethodKit details to `docs/macos-imk.md`, and
  DMG/release details to `docs/packaging.md`.
- GUI smoke testing, Chrome IME diagnostics, or debug IMK client range tracing:
  read `docs/testing.md`.
- App icon or input method icon assets: read `docs/icon.md`.
- DMG packaging, signing, notarization, stapling, or release workflow: read
  `docs/packaging.md`.
- Nix shells, Nix packages, Xcode build boundaries, `Makefile`, helper
  scripts, or version ownership: read `docs/toolchains.md`.

## Best Practices

- When implementation details are unclear, consult Real World References. These
  are reliable open-source projects that have been chosen by many users and are
  worth studying closely.
- Ghostty (`../ghostty`) is a useful reference for strong Nix usage that still
  accounts for Apple tools.
- Gureum (`../gureum`) is a useful precedent for macOS Korean input methods.
- libhangul (`../libhangul`) is a useful precedent for Hangul input models.
- Local clone paths can differ by developer. If the default reference paths do
  not exist, optionally check `AGENTS.local.md` for local reference paths.
  `AGENTS.local.md` is ignored by source control and is absent by default.
- Focused `docs/*` files may name the Real World Reference that applies to
  their ownership area. Keep local clone-path override mechanics here instead
  of repeating them in each focused document.

## Always Apply

- Prefer `make` targets for stable local workflows. Use `make help` to list
  available commands.
- Use the pinned Swift from `flake.nix` for Swift and SwiftPM work. Run Swift
  commands through `nix develop --ignore-environment --command -- swift ...`;
  do not call `/usr/bin/swift` directly.
- Run Xcode-oriented Make targets through the `xcode-work` shell, for example
  `nix develop .#xcode-work --command -- make build`.
- Do not run the input method directly from Xcode as the primary test path.
  Build it, install it into `~/Library/Input Methods`, then select it as an
  input source in System Settings.
- Keep helper scripts in Nushell and run them through the Nix dev shell.
- Keep InputMethodKit-specific code in `hisle/InputMethod/` thin. Put testable
  Hangul composition behavior in `hisle-core/` where possible.
- Use project terminology from `docs/terminology.md` in conversations,
  implementation notes, specs, and tests. In particular, use `대표 글쇠` for
  physical key labels based on standard US Qwerty, and do not translate
  `underlying roman layout`.

## Verification Routing

- For core behavior changes, run `make core-spec-check`.
- For InputMethodKit, mode switching, modifier handling, shortcut forwarding,
  or bundled CLI behavior changes, run `make gui-smoke-test` when local GUI
  prerequisites are available.
- For Chrome IME diagnostics, run `make chrome-ime-repro` when local GUI
  prerequisites are available.
- For icon changes, run `make icons` and build the app when relevant.
- For version ownership changes, run `make version-check`.
