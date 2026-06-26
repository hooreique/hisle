# Getting Started

## Requirements

- Binary install: macOS.
- Source install: Apple Silicon macOS, Xcode at `/Applications/Xcode.app`, and
  Nix with flakes enabled.

## Install From The Release DMG

Fastest: download the `.dmg` from
<https://github.com/hooreique/hisle/releases>, open it, and read the
`install.txt` inside.

Short version:

1. Copy `hisle.app` to `~/Library/Input Methods/`.
2. Open System Settings > Keyboard > Input Sources.
3. Add `hisle`, then select it from the input menu.

If `hisle` does not appear in Input Sources, log out and back in.

## Build And Install From Source

Use the Make target instead of launching the input method from Xcode:

```sh
nix develop .#xcode-work --command -- make install-debug
```

Then add and select `hisle` in System Settings > Keyboard > Input Sources.

## First Run

`hisle` starts in Roman mode. Tap left Shift by itself for Roman mode, and tap
right Shift by itself for Hangul mode.

Hangul mode uses a personal Cole Sebeol-based layout with `sane-punctuation`;
it is not meant to be a general Korean input method. Shortcut behavior and
mode-switching policy are described in `docs/input-modes.md`.

## Update Or Remove

To update a source install, rerun the install command above.

To remove from a source checkout:

```sh
make uninstall
```

Manual removal is just removing the installed bundle:

```sh
rm -rf "$HOME/Library/Input Methods/hisle.app"
```
