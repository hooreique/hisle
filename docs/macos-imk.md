# macOS IMK

This document covers the macOS app, InputMethodKit integration, input source
metadata, mode switching, shortcut forwarding, and the bundled companion CLI.
Read it before changing `hisle/App/`, `hisle/InputMethod/`, `hisle/Info.plist`,
`hisle-cli/`, or input-mode behavior.

## Scope

- `hisle/App/` contains the app lifecycle and input-method server startup.
- `hisle/InputMethod/` contains the InputMethodKit controller and server code.
- `hisle/Info.plist` contains input method metadata consumed by macOS.
- `hisle-cli/` contains the companion command-line helper bundled into
  `hisle.app/Contents/Helpers/hisle`.
- Keep InputMethodKit-specific code thin. Put testable Hangul composition
  behavior in `hisle-core/` where possible.

## Input Modes

Read `docs/input-modes.md` before changing input-mode state, left/right Shift
handling, Escape behavior, host action forwarding, shortcut forwarding, or the
boundary between Roman mode and Hangul mode.

The current visible input source is `hisle`. It starts in Roman mode with
Colemak output, uses Cole Sebeol in Hangul mode, and forwards host shortcuts
after flushing active composition.

Treat left Shift single tap as Roman mode selection and right Shift single tap
as Hangul mode selection, as specified in `docs/input-modes.md`.

Keep the current public input source focused on `hisle`. Add other visible
modes only after their user-facing behavior is specified.

Keep the top-level `TISInputSourceID` as the parent input method ID
(`hooreique.inputmethod.hisle`) and the visible mode ID as
`hooreique.inputmethod.hisle.main`; using the same ID for both creates duplicate
TIS entries.

## Commands

Build the macOS input method app:

```sh
nix develop --command -- make build
```

Debug install into `~/Library/Input Methods`:

```sh
nix develop --command -- make install-debug
```

Direct debug install script:

```sh
nix develop --command -- nu tools/install_debug.nu
```

Remove the local debug install:

```sh
nix develop --command -- make uninstall
```

Direct uninstall script:

```sh
nix develop --command -- nu tools/uninstall.nu
```

Do not run the input method directly from Xcode as the primary test path. Build
it, install it into `~/Library/Input Methods`, then select it as an input source
in System Settings.

For InputMethodKit, mode switching, modifier handling, shortcut forwarding, or
bundled CLI behavior changes, run
`nix develop --command -- make gui-smoke-test` when the local GUI prerequisites
are available. The GUI smoke test details live in `docs/testing.md`.

## Companion CLI

Installed helper path after a debug install:

```sh
"$HOME/Library/Input Methods/hisle.app/Contents/Helpers/hisle"
```

Without options it prints `roman` or `hangul`; `--version` prints both the app
version and `hisle-core` version. Debug CLI builds append `-debug` to the
displayed app version.

When changing `hisle-cli`, update this Companion CLI section and the GUI smoke
test expectations if the command-line contract changes. The bundled helper's
no-option output is part of the smoke test.

## Logging

All builds emit `controller runtime` lifecycle notices when an input method
controller is initialized or activated. Each notice includes `stage`,
`buildProfile`, `appVersion`, `coreVersion`, `build`, `pid`, `bundle`, and
`replacementPolicy` so Debug and Release binaries can be matched to the
installed app and core library being tested, even when a manual `log stream`
starts after the process was launched. The `buildProfile` field is `debug` or
`release`; the `build` field comes from `CFBundleVersion`, which is owned by
`CURRENT_PROJECT_VERSION`.

Debug builds can opt into noisy IMK client range traces with the
`traceClientRanges` defaults key or `HISLE_TRACE_CLIENT_RANGES=1`; see
`docs/testing.md`.

Release builds must not emit these traces. Keep any Release logging limited to
sparse lifecycle or unexpected fallback events.

## Marked Text Range Policy

For ordinary current-selection insertion, use
`NSRange(location: NSNotFound, length: 0)` instead of converting
`selectedRange()` into an explicit document range. Some browser and custom
editor clients can report stale or restored selections across IMK composition
boundaries.

While `hisle` owns an active marked text sequence, it tracks the marked range
and the collapsed insertion range created by its own marked-text updates and
composition commits. Use the owned marked range for replacing active marked
text, and use the owned collapsed insertion range only to place the next
marked-text update after a composition commit. Ordinary committed text with no
active marked text must still use the current-selection sentinel and must not
create or preserve an owned insertion range, because browser and rich-editor
clients can report unstable explicit document ranges during plain Roman or
standalone punctuation input. Clear owned ranges on user or host actions that
can legitimately move the caret: mouse down, host-forwarded navigation/action
keys, mode changes, deactivation, and external cancel/commit boundaries.

After `insertText(_:replacementRange:)` for an active composition commit, prefer
a valid collapsed `selectedRange()` from the client as the next owned insertion
point only when the pre-commit host selection was inconsistent with the owned
replacement range. Some hosts remap IMK coordinates after a commit; deriving
continuation by arithmetic from the pre-commit replacement range can point at
the wrong document position in the middle of rich editor content. When the
pre-commit host selection is already consistent with the owned replacement
range, derive continuation from that replacement range plus the committed text
length, because fast browser input can expose a transient post-commit
`selectedRange()` that is ahead of the intended caret. A non-collapsed
pre-commit selection is consistent only when both its start and end match the
owned replacement range; sharing just one boundary can be stale host state. A
collapsed selection remains compatible at the replacement start, end, or one
UTF-16 position after the end.

For a whitespace `FlushThenEmit` boundary that closes active Hangul marked text,
commit the active composition and the whitespace as separate host insertions.
The active composition still uses the owned marked-text replacement range.
Schedule the whitespace insertion on the next main-queue turn, then send it
through the current-selection sentinel. This lets browser editors finish their
composition-end selection update before the plain whitespace insertion; otherwise
Chrome/Confluence can insert the space but restore the caret to the position
before that space. Advance the owned insertion range by the whitespace length
for the next marked-text update, but do not let this rule apply to ordinary
plain commits with no active marked text.

Keep this policy app-agnostic. Do not add Confluence, Chromium, or editor-name
branches unless a later bug proves that a general IMK range policy is
insufficient.

## References

- Use `../gureum` (https://github.com/gureum/gureum) as the reference for app
implementation and InputMethodKit behavior.
