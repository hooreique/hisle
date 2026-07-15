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

For bundled CLI behavior changes, run
`nix develop --command -- make hisle-cli-check`; also run
`nix develop --command -- make frontmost-monitor-check` when monitor behavior
changes. For InputMethodKit, mode switching, modifier handling, shortcut
forwarding, or CLI mode integration, run
`nix develop --command -- make gui-smoke-test` when the local GUI prerequisites
are available. The check details live in `docs/testing.md`.

## Companion CLI

Installed helper path after a debug install:

```sh
"$HOME/Library/Input Methods/hisle.app/Contents/Helpers/hisle"
```

Without options it prints `roman` or `hangul`; `--version` prints both the app
version and `hisle-core` version. Debug CLI builds append `-debug` to the
displayed app version.

`hisle init` creates the resolved `busy-apps.txt` and any missing parent
directories, then prints the path. It uses the same XDG/HOME precedence as the
app, is safe to repeat, and never truncates an existing file. App startup
remains read-only and does not create a missing configuration file. An existing
`busy-apps.txt` may be a symbolic link when it resolves to a regular file;
directories, other non-regular targets, and broken links are rejected.

`hisle frontmost` prints the current frontmost app's bundle identifier
immediately, then prints one unadorned line whenever the identifier changes.
It suppresses consecutive duplicate identifiers. If an app has no bundle
identifier, the helper reports that fact on stderr and continues monitoring.
The no-option and `--version` contracts are unchanged.

When changing `hisle-cli`, update this Companion CLI section and the relevant
CLI, frontmost-monitor, and GUI smoke expectations. The bundled helper's
no-option output is part of both the CLI and GUI checks.

## Logging

At startup, all builds log the resolved `busy-apps.txt` path and snapshot entry
count before starting the IMK server. A missing, unreadable, or invalid UTF-8
file produces an empty snapshot and an error notice containing the read cause.

All builds emit `controller runtime` lifecycle notices when an input method
controller is initialized or activated. Each notice includes `stage`,
`buildProfile`, `appVersion`, `coreVersion`, `build`, `pid`, `bundle`,
`clientBundleIdentifier`, `profile`, and `replacementPolicy` so Debug and
Release binaries, client identity, and selected backend can be matched to the
installed app and core library being tested, even when a manual `log stream`
starts after the process was launched. The `profile` field is `default` or
`busy`; an unidentified client is logged as `unknown` and uses `default`. The
`buildProfile` field is `debug` or `release`; the `build` field comes from
`CFBundleVersion`, which is owned by `CURRENT_PROJECT_VERSION`.

Debug builds can opt into noisy IMK client range traces with the
`traceClientRanges` defaults key or `HISLE_TRACE_CLIENT_RANGES=1`; see
`docs/testing.md`.

Release builds must not emit these traces. Keep any Release logging limited to
sparse lifecycle or unexpected fallback events.

## App-Specific Host Backends

`AppDelegate` loads one immutable `BusyAppsSnapshot` before
`InputMethodServer` starts. A controller reads its initial
`IMKTextInput.bundleIdentifier()` without normalization and selects `busy` only
for an exact, case-sensitive snapshot member; every other client selects
`default`. The selected backend is fixed for the controller lifetime.

`InputController` owns only the IMK overrides and routes activation,
deactivation, close, `setValue`, mouse and key events, mode boundaries,
forwarding, Backspace, engine output application, Roman commits, fallback,
external commit/cancel, composition updates, replacement-range callbacks, and
deferred callbacks to that one backend.

Both backends share the Cole Sebeol engine type, key classifier, Shift detector,
and input-mode policy, but each backend instance owns its own engine and marked
state. `DefaultHostBackend` additionally owns only the v0.1.8 single pending
marked-text continuation. `BusyHostBackend` owns the marked-range tracker,
deferred queue, editing-context generation, tickets, and in-flight commit,
aggregate, and continuation state. Do not move pending or deferred state back
onto `InputController` or share it across the backends.

### Default Marked Text Policy

`default` restores the complete v0.1.8 host-integration behavior. It queries
the client selected and marked ranges for each commit, replaces a valid host
marked range only while local marked text is active, and otherwise uses
`NSRange(location: NSNotFound, length: 0)`. A commit followed by new marked text
uses one pending continuation range for that immediate `updateComposition`
callback only.

`FlushThenEmit` output, including active Hangul composition plus whitespace, is
inserted synchronously as the engine's full committed string in one host call.
Hangul fallback text is processed and applied scalar by scalar. Default has no
owned-range tracker, deferred queue, generation, ticket, aggregate transaction,
or close-time flush beyond the v0.1.8 lifecycle.

### Busy Marked Text Range Policy

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
standalone punctuation input. Do not query `selectedRange()` or `markedRange()`
to make that plain-commit decision; the commit replacement decision reads those
host ranges only while active marked text is being committed. Clear owned ranges
on user or host actions that can legitimately move the caret: mouse down,
host-forwarded navigation/action keys, mode changes, deactivation, and external
cancel/commit boundaries.

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

Treat an accepted deferred boundary as session-owned input that must be emitted
exactly once. Bind it to the originating IMK client, active editing-context
generation, owned insertion-range snapshot, and a unique ticket. Resolve queued
boundaries before any later scalar, key event, host action, mode or focus
change, external commit/cancel, deactivation, or controller close; a scheduled
callback whose ticket was already drained is a no-op. A multi-scalar fallback
that reaches a deferred boundary keeps its remaining scalars as that ticket's
continuation, so they run after the boundary instead of overtaking it in the
same call stack. Fold a host-inactive continuation through a copy of the Hangul
engine before its next host mutation, then publish the engine and apply the
aggregate committed/marked output through one phase-owned transaction. The
transaction must be visible before the first host call, including range reads,
and reentrant lifecycle drains must finish its commit, selection, marked-text,
and marked-range phases exactly once. Deferred delivery must not clear newer
marked text, reinterpret the continuation through a later shared input mode, or
reroute the boundary to a different client.

Keep each backend internally app-agnostic. App identity selects the backend
only through the external exact-match snapshot; do not add Confluence,
Chromium, Teams, or editor-name branches or built-in identifiers.

## References

- Use `../gureum` (https://github.com/gureum/gureum) as the reference for app
implementation and InputMethodKit behavior.
