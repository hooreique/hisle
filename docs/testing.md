# Testing

This document keeps long-lived verification procedures for `hisle`.

## GUI Smoke Test

Run this as a separate GUI check because InputMethodKit modifier-event delivery
must be verified with real GUI focus.

Preferred command:

```sh
make gui-smoke-test
```

This target runs the core contract/spec check, builds and installs the debug
input method, opens a temporary file in Sublime Text, selects the `hisle` input
source, streams `hisle` logs, sends the GUI key sequence, saves the temporary
file through Sublime Text, and verifies the saved file content automatically.

The command exiting with status 0 means the scripted setup, key sequence,
Colemak-underlying Command+S save path, and saved file content verification all
passed. The same script also invokes the bundled
`hisle.app/Contents/Helpers/hisle` helper after Roman/Hangul mode transitions
and verifies that it prints the current mode.

To run only the GUI driver after a debug install:

```sh
nix develop --command -- nu tools/gui_smoke_test.nu
```

Requirements:

- Sublime Text must be installed. Do not use TextEdit for this smoke test.
- The terminal process running the script must have macOS Accessibility
  permission so it can send GUI key events.
- Sublime Text cold start can be slow. The driver waits for the app, the smoke
  file window, and frontmost focus before sending key events.
- Do not type or change focus while the script is running.

Scripted smoke sequence:

- Type the physical representative `E` key before any Shift mode selection.
  The initial mode should be Roman, so the document should begin with Colemak
  output `f`.
- Tap right Shift once. It should select Hangul mode and commit no text.
  The bundled `hisle` CLI should print `hangul`.
- Type the physical representative `` ` `` key. Hangul-mode sane-punctuation
  handling should commit a literal backtick.
- Type representative keys `j g d`, then press Escape. Escape should flush the
  active `의` composition instead of clearing it, select Roman mode, and still
  pass Escape through to Sublime Text.
  The bundled `hisle` CLI should print `roman`.
- Type the physical representative `E` key. Because Escape selected Roman mode,
  this should emit Colemak output `f`.
- Tap right Shift once to select Hangul mode again, then type representative
  keys `j t b`. The visible text after the initial backtick should become
  `의f어ㅜ`: `j g d` verifies `ㅢ` composition, and `j t b` verifies that
  representative `t b` stays `어ㅜ` instead of composing `워`.
- Press Command with physical representative `D`. Because the `hisle` input
  source declares Colemak as its `KeyboardLayout`, this should be delivered to
  Sublime Text as Command+S, flush the active Hangul composition, save the
  temporary file, and leave saved file content ``f`의f어ㅜ``.
- Tap left Shift once. It should select Roman mode and commit no Shift text.
  The bundled `hisle` CLI should print `roman`.
- Type the physical representative `E` key. Roman mode should emit Colemak
  output `f`, so the document text should be exactly
  ``f`의f어ㅜf``.
- Press Command with physical representative `D` again. This should save the
  Roman-mode text through the same Colemak-underlying shortcut path, and
  the script verifies that the saved file content is exactly
  ``f`의f어ㅜf``.
- Tap right Shift once to select Hangul mode, switch to another available input
  source, then select `hisle` again. Returning to `hisle` should enter Roman
  mode, so typing physical representative `E` should append Colemak output `f`.
  The bundled `hisle` CLI should print `hangul` before switching away and
  `roman` after returning to `hisle`.
- Press Command with physical representative `D` again. This should save the
  final round-trip text through the same shortcut path, and the script verifies
  that the saved file content is exactly ``f`의f어ㅜff``.
- Watch the terminal log stream for `hisle` key and mode events while the
  sequence runs.

This smoke test passes only if the final saved file content is exactly
``f`의f어ㅜff`` and no extra Shift-related text appears in the saved file.

Known non-issues:

- Xcode may print CoreSimulator version warnings while building this macOS input
  method target. Treat them as noise unless the build fails.
- Xcode may print AppIntents metadata extraction warnings such as skipped
  metadata or no AppIntents dependency found. Treat them as noise unless the
  build fails.

## Chrome IME Reproduction

Use this as a diagnostic tool for Chrome `<textarea>`, `contenteditable`, and
WYSIWYG behavior that must pass through the real macOS input method path.
Playwright launches and observes Chrome, but all typing is sent by the Swift HID
driver.

Preferred command:

```sh
make chrome-ime-repro
```

To run only the repro after a debug install:

```sh
nix develop .#browser-work --command -- nu tools/chrome_ime_repro.nu
```

Useful environment options:

- `SEED`, default `1`.
- `ITERATIONS`, default `1`.
- `RUN_ID`, default timestamp plus a short random suffix.
- `CHROME_PATH`, optional path to Chrome or Chrome for Testing.
- `CHROME_REMOTE_DEBUGGING_PORT`, optional fixed Chrome remote debugging port.
- `HISLE_CHROME_KEEP_OPEN=1`, leave Chrome open after artifact capture.
- `HISLE_CHROME_TARGET`, one of `textarea`, `contenteditable`, or `wysiwyg`;
  default `textarea`.
- `HISLE_CHROME_SCENARIO`, one of `standard`, `click-during-composition`,
  `idle-stress`, `midline-insert`, `two-insert-move`,
  `active-move-continue`, or `click-move-continue`; default `standard`.
- `HISLE_CHROME_EDITOR_CHAOS`, optional WYSIWYG editor maintenance simulation:
  `idle-normalize`, `focus-pulse`, `active-rerender`, or
  `active-rerender-focus-pulse`.
- `HISLE_CHROME_IDLE_MS`, `HISLE_CHROME_CHAOS_DELAY_MS`, and
  `HISLE_CHROME_DELAY_MIN_MS`/`HISLE_CHROME_DELAY_MAX_MS` tune the HID and idle
  timings.
- `HISLE_CHROME_INITIAL_TEXT` and `HISLE_CHROME_INITIAL_CARET` seed the target
  text and caret offset.
- `HISLE_CHROME_INITIAL_RENDER`, one of `text`, `spans`, or `paragraphs`;
  `paragraphs` maps newline-separated WYSIWYG text to `<p data-line>` blocks.
- `HISLE_CHROME_MOVE_AFTER_COMPOSITION_CARET` and
  `HISLE_CHROME_MOVE_AFTER_INPUT_CARET` move the DOM selection during active
  composition without using Playwright for text entry. Use these to reproduce
  editor-side selection drift.
- `HISLE_CHROME_CLICK_AFTER_INPUT_CARET` gives the driver a post-composition
  caret target for the `click-move-continue` scenario. If Chrome screen-point
  estimation is off in the local environment, tune the HID click with
  `HISLE_CHROME_CLICK_SCREEN_DX` and `HISLE_CHROME_CLICK_SCREEN_DY`.
- `HISLE_CHROME_SKIP_FOCUS_CLICK=1` skips the initial window-center focus
  click after Chrome is already frontmost.
- `HISLE_CHROME_CLICK_INITIAL_CARET=1` asks the driver to click the observer's
  initial caret screen point before typing.
- `HISLE_CHROME_FORCE_RENDER_ON_COMPOSITION_END=1` asks the WYSIWYG fixture to
  re-render after composition ends.
- `EXPECTED_VALUE` overrides the final-value assertion.
- `HISLE_CHROME_ALLOW_MISMATCH=1` keeps the run successful while preserving the
  observed mismatch in artifacts; use this for destructive repro scenarios.

Artifacts are written under `build/chrome-ime/<run-id>/`:

- `keys.jsonl`: Swift HID key-down/key-up events with sequence numbers,
  timestamps, key codes, flags, and planned delay.
- `dom-events.jsonl`: capture-phase DOM keyboard, composition, input,
  selection, focus, and blur events.
- `editor-chaos.jsonl`: editor maintenance events for WYSIWYG chaos scenarios.
- `ime.log`: unified log stream for `hooreique.inputmethod.hisle`.
- `final-state.json`: final value, HTML for non-textarea targets, selection,
  expected value, match result, and anomaly counters.
- `screenshot.png`: final browser screenshot.
- `trace.zip`: Playwright trace.
- `environment.json`: run metadata, tool versions, selected input source, and
  timing checkpoints.

Triage guide:

- Missing or bad IME operation logs usually points at `hisle`.
- Good IME logs with bad DOM events or textarea value points at the
  Chrome/macOS/browser interaction.
- Good DOM events followed by later value mutation points at page JavaScript.

### Debug Client Range Trace

Debug builds can emit opt-in `IMKTextInput` range traces for cursor and marked
text bugs. The trace records stage names, `selectedRange`, `markedRange`,
replacement range decisions, and marked-text lengths. It does not log raw input
text, and it is compiled out of Release builds.

Enable it for an installed Debug build:

```sh
defaults write hooreique.inputmethod.hisle traceClientRanges -bool YES
```

Disable it after the run:

```sh
defaults delete hooreique.inputmethod.hisle traceClientRanges
```

For directly launched debug processes, `HISLE_TRACE_CLIENT_RANGES=1` enables the
same trace.
