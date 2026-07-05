# Testing

This document keeps long-lived verification procedures for `hisle`.

## GUI Smoke Test

Run this as a separate GUI check because InputMethodKit modifier-event delivery
must be verified with real GUI focus.

Preferred command:

```sh
nix develop --command -- make gui-smoke-test
```

This target builds and installs the debug input method, opens a temporary file
in Sublime Text, selects the `hisle` input source, streams `hisle` logs, sends
the GUI key sequence, saves the temporary file through Sublime Text, and
verifies the saved file content automatically.

The command exiting with status 0 means the scripted setup, key sequence,
Colemak-underlying Command+S save path, and saved file content verification all
passed. The same script also invokes the bundled
`hisle.app/Contents/Helpers/hisle` helper after Roman/Hangul mode transitions
and verifies that it prints the current mode.

To run only the GUI driver after a debug install:

```sh
nix develop --command -- nu tools/gui_smoke_test.nu
```

The GUI driver imports Cocoa and ApplicationServices, so the script compiles it
with Xcode's `xcrun swiftc`, not the pinned Nix Swift used by `hisle-core`.

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

- The first run after a debug install may occasionally fail once while waiting
  for the final input-source round trip to become active. If the setup looked
  correct and focus was not changed manually, rerun
  `nix develop --command -- make gui-smoke-test` once before treating it as a
  regression.
- Xcode may print CoreSimulator version warnings while building this macOS input
  method target. Treat them as noise unless the build fails; see
  `docs/toolchains.md#known-xcode-warnings`.
- Xcode may print AppIntents metadata extraction warnings such as skipped
  metadata or no AppIntents dependency found. Treat them as noise unless the
  build fails; see `docs/toolchains.md#known-xcode-warnings` before changing
  build settings or linking frameworks.

## Chrome IME Reproduction

Use this as a diagnostic tool for Chrome `<textarea>`, `contenteditable`, and
WYSIWYG behavior that must pass through the real macOS input method path.
Playwright launches and observes Chrome, but all typing is sent by the Swift HID
driver.

Preferred command:

```sh
nix develop .#browser --command -- make chrome-ime-repro
```

To run only the repro after a debug install:

```sh
nix develop .#browser --command -- nu tools/chrome_ime_repro.nu
```

The Swift HID driver imports macOS frameworks, so the script compiles it with
Xcode's `xcrun swiftc`. Keep the pinned Nix Swift reserved for pure
`hisle-core` commands in the `core` shell.

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
  `active-move-continue`, `click-move-continue`, `drag-selection-input`,
  `selected-range-input`, `selected-range-numbers`,
  `selected-range-annyeonghaseyo`, `stale-selection-annyeonghaseyo`,
  `annyeong-words`, `annyeong-word-repeats`, or
  `double-click-selection-annyeonghaseyo`;
  `selected-range-annyeonghaseyo` is a focused selected-text regression repro,
  `stale-selection-annyeonghaseyo` combines default contenteditable text,
  double-click selection, stale selection restoration, and expected final value
  `안녕하세요`, `annyeong-words` types `안 녕 안 녕` through real Hangul
  composition for prefix-insertion regressions with existing textarea text,
  `annyeong-word-repeats` types repeated `안녕` words before existing text, and
  `double-click-selection-annyeonghaseyo` double-clicks the
  `HISLE_CHROME_INITIAL_CARET` point before typing; default `standard`.
- `HISLE_CHROME_EDITOR_CHAOS`, optional WYSIWYG editor maintenance simulation:
  `idle-normalize`, `focus-pulse`, `active-rerender`, or
  `active-rerender-focus-pulse`; `restore-initial-selection` restores the
  initial `start:end` selection after each composition end to model stale host
  selection state.
- `HISLE_CHROME_IDLE_MS`, `HISLE_CHROME_CHAOS_DELAY_MS`, and
  `HISLE_CHROME_DELAY_MIN_MS`/`HISLE_CHROME_DELAY_MAX_MS` tune the HID and idle
  timings.
- `HISLE_CHROME_INITIAL_TEXT` and `HISLE_CHROME_INITIAL_CARET` seed the target
  text and caret offset.
- `HISLE_CHROME_INITIAL_SELECTION` seeds the target selection in `start:end`
  form. It is useful with `selected-range-input`, which preserves that selection
  and sends real HID key input through the input method.
- `HISLE_CHROME_INITIAL_DOUBLE_CLICK=1` asks the observer to double-click the
  `HISLE_CHROME_INITIAL_CARET` point using Chrome mouse events before the Swift
  HID driver starts typing.
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
- `HISLE_CHROME_DRAG_SELECTION` gives `drag-selection-input` a textarea offset
  range in `start:end` form. The HID driver drags that range, switches to
  Hangul mode, types the first representative `j` key, and captures the active
  composition state.
- `HISLE_CHROME_SKIP_FOCUS_CLICK=1` skips the initial window-center focus
  click after Chrome is already frontmost.
- `HISLE_CHROME_CLICK_INITIAL_CARET=1` asks the driver to click the observer's
  initial caret screen point before typing.
- `HISLE_CHROME_FORCE_RENDER_ON_COMPOSITION_END=1` asks the WYSIWYG fixture to
  re-render after composition ends.
- `EXPECTED_VALUE` overrides the final-value assertion.
- `HISLE_CHROME_ALLOW_MISMATCH=1` keeps the run successful while preserving the
  observed mismatch in artifacts; use this for destructive repro scenarios.

### Selected Range Regression Scenarios

Use these scenarios to check selected-range replacement behavior through the
Chrome IME diagnostics.

First run the control. It selects `가나다라마바사` in contenteditable and types
`안녕하세요`; the final value should be the full replacement:

```sh
env \
  HISLE_CHROME_TARGET=contenteditable \
  HISLE_CHROME_SCENARIO=selected-range-annyeonghaseyo \
  HISLE_CHROME_INITIAL_TEXT='가나다라마바사' \
  HISLE_CHROME_INITIAL_SELECTION='0:7' \
  EXPECTED_VALUE='안녕하세요' \
  nix develop .#browser --command -- nu tools/chrome_ime_repro.nu
```

Then run the stale-selection model. It uses the same contenteditable surface,
double-click selection, and `restore-initial-selection` editor chaos. The
expected final value is `안녕하세요`; a selected-range regression usually returns
only the last unit, `요`:

```sh
env \
  HISLE_CHROME_SCENARIO=stale-selection-annyeonghaseyo \
  RUN_ID=stale-selection-annyeonghaseyo \
  nix develop .#browser --command -- nu tools/chrome_ime_repro.nu
```

This scenario is a focused fixture for stale host/client range behavior; inspect
the artifacts to confirm which layer reported or restored the selected range.

Artifacts are written under `build/chrome-ime/<run-id>/`:

- `keys.jsonl`: Swift HID key-down/key-up events with sequence numbers,
  timestamps, key codes, flags, and planned delay.
- `dom-events.jsonl`: capture-phase DOM keyboard, composition, input,
  selection, focus, and blur events.
- `editor-chaos.jsonl`: editor maintenance events for WYSIWYG chaos scenarios.
- `ime.log`: unified log stream for `hooreique.inputmethod.hisle`.
- `runtime-identity.log`: post-run unified log snapshot of the running input
  method app version, bundle path, process id, and replacement policy.
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

## Firefox IME Reproduction

Use this as the Firefox counterpart to the local Chrome IME fixture. It launches
real Firefox through Selenium and geckodriver, observes DOM events from the same
`<textarea>`, `contenteditable`, and WYSIWYG fixture, and still sends all typing
through the Swift HID driver and the real macOS input method path.

Preferred command:

```sh
nix develop .#browser --command -- make firefox-ime-repro
```

To run only the repro after a debug install:

```sh
nix develop .#browser --command -- nu tools/firefox_ime_repro.nu
```

Firefox does not use the Chrome DevTools Protocol attach path from the Chrome
fixture. The local fixture starts a WebDriver-controlled Firefox session through
geckodriver instead, so `CHROME_REMOTE_DEBUGGING_PORT` and Chrome reuse options
do not apply. The browser shell provides geckodriver, and the script defaults to
`/Applications/Firefox.app/Contents/MacOS/firefox` when `FIREFOX_PATH` and
`HISLE_FIREFOX_PATH` are unset.

Useful environment options mirror the Chrome fixture. Prefer the
`HISLE_FIREFOX_*` names for Firefox-specific runs, such as
`HISLE_FIREFOX_TARGET`, `HISLE_FIREFOX_SCENARIO`,
`HISLE_FIREFOX_INITIAL_TEXT`, `HISLE_FIREFOX_INITIAL_SELECTION`,
`HISLE_FIREFOX_EDITOR_CHAOS`, `HISLE_FIREFOX_ALLOW_MISMATCH`, and
`HISLE_FIREFOX_KEEP_OPEN`. Existing `HISLE_CHROME_*` names remain accepted as a
fallback for the shared local fixture options.

Artifacts are written under `build/firefox-ime/<run-id>/` and match the Chrome
fixture where possible: `keys.jsonl`, `dom-events.jsonl`,
`editor-chaos.jsonl`, `ime.log`, `runtime-identity.log`, `driver-state.json`,
`final-state.json`, `screenshot.png`, and `environment.json`. Selenium does not
produce Playwright `trace.zip` artifacts.

## Atlassian Confluence Live Reproduction

Use this when the behavior must be checked against a real Confluence Cloud page
instead of the local Chrome IME fixture. The test uses a separate persistent
Chrome profile under `local/atlassian/chrome-profile/` so Atlassian cookies and
site data survive across runs. Artifacts are written under
`local/atlassian/runs/<run-id>/`. The whole `local/` tree is ignored by Git and
can contain private session data.

Configure the target page with either `ATLASSIAN_CONFLUENCE_URL` or
`local/atlassian/config.json`:

```json
{
  "page_url": "https://<site>.atlassian.net/wiki/spaces/<space>/pages/<page>/<title>",
  "email": "<optional login email>"
}
```

The older `local/atlassianinfo` form, `<site> <email>`, is still accepted as a
fallback for opening the site, but use `page_url` for the live-page repro so the
observer can navigate directly to the test page.

First create or refresh the browser login session:

```sh
nix develop .#browser --command -- make atlassian-confluence-login
```

This opens normal Chrome, not a Playwright-controlled browser, with the
persistent Atlassian profile. Complete the normal Atlassian login and email
verification in the browser, wait until the target page is usable, then quit
that Chrome instance with Command-Q so the profile can be reused by the repro.
The script does not automate login or bypass verification; it only preserves
the resulting browser state for later runs.

Some Atlassian login policies can still ask for a fresh login when the repro
opens Chrome with a remote debugging port. If the repro stops on the Atlassian
login page, complete that login in the Chrome window it opened, leave the window
open, and rerun the script against the same remote debugging port:

```sh
env \
  HISLE_ATLASSIAN_REUSE_CHROME=1 \
  CHROME_REMOTE_DEBUGGING_PORT=<port> \
  nix develop .#browser --command -- nu tools/atlassian_confluence_repro.nu
```

Run the live Confluence repro:

```sh
nix develop .#browser --command -- make atlassian-confluence-repro
```

The target builds and installs the debug input method, opens the configured
Confluence page with the persistent profile, clicks the page Edit action when an
editor is not already open, focuses the first usable editor `contenteditable`,
selects `hisle`, and types `안녕하세요` through the Swift HID driver. It does not
publish the page. Use a disposable Confluence page because the editor can still
autosave drafts.

Useful environment options:

- `ATLASSIAN_CONFLUENCE_URL` or `HISLE_ATLASSIAN_URL`, target page URL.
- `HISLE_ATLASSIAN_PROFILE_DIR`, override the persistent Chrome profile path.
- `HISLE_ATLASSIAN_TARGET_SELECTOR`, CSS selector for the editor if automatic
  detection picks the wrong `contenteditable`.
- `HISLE_ATLASSIAN_INITIAL_CARET_OFFSET`, optional text offset for the initial
  Confluence caret. Use a non-negative DOM Range text offset or `middle`; when
  set, the final assertion checks the full expected Range text, not only
  whether the inserted substring appears somewhere. The artifact still records
  the editor's visible `innerText` separately as `value`.
- `HISLE_ATLASSIAN_STRICT_FULL_TEXT=1`, require the same full expected Range
  text assertion even when the caret offset is auto-discovered rather than
  explicitly configured.
- `HISLE_ATLASSIAN_EDIT=0`, require the page to already be in edit mode.
- `HISLE_ATLASSIAN_EXPECTED_TEXT`, final text substring expected in the editor;
  the driver sequence currently types the default `안녕하세요`.
- `HISLE_ATLASSIAN_SCENARIO=annyeonghaseyo-words`, type repeated
  `안녕하세요` words separated by spaces. Combine with
  `HISLE_ATLASSIAN_WORD_COUNT`, default `3`, to reproduce cursor jumps during
  ordinary multi-word Hangul input.
- `HISLE_ATLASSIAN_SCENARIO=annyeong-space-backspace`, type `안녕`, press
  Space, then press Backspace. The expected inserted text defaults to `안녕`;
  combine it with `HISLE_ATLASSIAN_INITIAL_CARET_OFFSET` for a strict full-text
  assertion inside existing Confluence content.
- `HISLE_ATLASSIAN_SCENARIO=foo-bar-annyeong-space-backspace`, type `foo bar`
  in Roman mode, move the caret back to immediately after `foo`, type `안녕 `,
  then press Backspace. The expected visible text defaults to `foo안녕 bar`.
- `HISLE_ATLASSIAN_SCENARIO=roman-foo-bar`, type visible Roman text
  `foo bar foo bar` through hisle Roman mode.
- `HISLE_ATLASSIAN_SCENARIO=roman-text` with `HISLE_ATLASSIAN_ROMAN_TEXT`,
  type a custom visible lowercase Roman text string through hisle Roman mode.
- `HISLE_ATLASSIAN_HANGUL_BEFORE_EDITOR_CLICK=1`, select Hangul mode before
  focusing the Confluence editor. Use this to verify the intended fresh
  app/client Roman-mode initialization and to observe cursor placement at the
  start of editing.
- `HISLE_ATLASSIAN_KEEP_OPEN=1`, leave Chrome open after artifact capture.
- `HISLE_ATLASSIAN_ALLOW_MISMATCH=1`, keep the run successful while preserving
  the observed mismatch in artifacts.
- `CHROME_PATH`, optional path to Chrome or Chrome for Testing.
- `CHROME_REMOTE_DEBUGGING_PORT`, optional fixed Chrome remote debugging port.
- `HISLE_ATLASSIAN_REUSE_CHROME=1`, connect to an already-open Chrome on
  `CHROME_REMOTE_DEBUGGING_PORT` instead of launching a new one.
- `RUN_ID`, stable run directory name under `local/atlassian/runs/`.

Artifacts:

- `keys.jsonl`: Swift HID key-down/key-up events.
- `dom-events.jsonl`: capture-phase DOM keyboard, composition, input, selection,
  focus, and blur events from the Confluence page.
- `console.jsonl`: browser console and page-error records.
- `ime.log`: unified log stream for `hooreique.inputmethod.hisle`.
- `runtime-identity.log`: post-run unified log snapshot of the running input
  method app version, bundle path, process id, and replacement policy.
- `driver-state.json`, `observer-ready.json`, and `environment.json`: run
  metadata, selected input source, profile path, page URL, and timing data.
- `final-state.json`: final editor text summary, expected-text match, and event
  anomaly counters.
- `screenshot.png` and `trace.zip`: final page screenshot and Playwright trace.

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
