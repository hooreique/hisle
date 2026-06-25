# Getting Started

This is a small, intentionally low-profile install and first-run guide for
people who already decided they want to try `hisle`. Keep project motivation
and contribution stance in `README.md`; keep build-system detail in
`docs/toolchains.md`, `docs/macos-imk.md`, and `docs/packaging.md`.

## Prerequisites

For binary use:

- macOS.
- A built `hisle.app` bundle, usually from a DMG.

For source builds:

- Apple Silicon macOS. The checked-in Nix flake targets `aarch64-darwin`.
- Xcode installed, normally at `/Applications/Xcode.app`.
- Nix with flakes enabled.

For scripted GUI verification, see `docs/testing.md`; it has extra requirements
such as Sublime Text and Accessibility permission.

## Install From A DMG

1. Open the DMG.
2. Copy `hisle.app` to `~/Library/Input Methods/`.
3. Open System Settings > Keyboard > Input Sources.
4. Add `hisle`, then select it from the input menu.

If `hisle` does not appear in Input Sources after copying the app, log out and
back in, then check again.

## Build And Install From Source

Use the Make target instead of launching the input method directly from Xcode:

```sh
nix develop .#xcode-work --command -- make install-debug
```

Then add and select `hisle` in System Settings > Keyboard > Input Sources.

To confirm the bundled helper was installed:

```sh
"$HOME/Library/Input Methods/hisle.app/Contents/Helpers/hisle" --version
```

## First Run

`hisle` starts in Roman mode. Tap left Shift by itself to select Roman mode, and
tap right Shift by itself to select Hangul mode.

Hangul mode uses a personal Cole Sebeol-based layout with `sane-punctuation`;
it is not meant to be a general Korean input method. Shortcut behavior and
mode-switching policy are described in `docs/input-modes.md`.

## Update Or Remove

To replace a source install, rerun:

```sh
nix develop .#xcode-work --command -- make install-debug
```

To remove the local install:

```sh
make uninstall
```

Manual removal is just removing the installed bundle:

```sh
rm -rf "$HOME/Library/Input Methods/hisle.app"
```

Local DMG creation, signing, notarization, and release packaging are covered in
`docs/packaging.md`.
