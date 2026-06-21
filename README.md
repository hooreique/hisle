# hisle

hisle is a small macOS input method. The Korean name is `이슬`, the
international name is `hisle`, and the pronunciation is `/i.sɯl/`.

For Korean documentation, see [README.ko.md](README.ko.md).

## Status

hisle provides one macOS input source, `hisle`. It starts in Roman mode with
Colemak output, uses Cole Sebeol in Hangul mode, and uses left/right Shift
single taps to select Roman/Hangul mode. When you return to `hisle` from another
input source, it enters Roman mode.

## Install From Source

You need macOS, Xcode, and Nix available in this checkout.

```sh
make install-debug
```

This builds the app and installs it into `~/Library/Input Methods`.

## Select Input Source

Open System Settings > Keyboard, add `hisle` as an input source, and select
`hisle` from the input menu to use it.

## Use

- Left Shift single tap selects Roman mode.
- Right Shift single tap selects Hangul mode.
- Escape commits the active Hangul composition, selects Roman mode, and still
  reaches the current app.

## Companion CLI

The installed bundle includes a small `hisle` helper:

```sh
"$HOME/Library/Input Methods/hisle.app/Contents/Helpers/hisle"
"$HOME/Library/Input Methods/hisle.app/Contents/Helpers/hisle" --version
"$HOME/Library/Input Methods/hisle.app/Contents/Helpers/hisle" --help
```

Without options, it prints the current mode: `roman` or `hangul`. `--version`
prints the app and `hisle-core` versions, and `--help` prints usage.

## Remove

```sh
make uninstall
```

Maintainer and development instructions live in [AGENTS.md](AGENTS.md).
