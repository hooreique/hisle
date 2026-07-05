# Stale Selected Range Replacement Report

## Summary

When a non-collapsed selection exists in a browser or editor host, typing a
multi-unit sequence can leave only the final committed unit visible. The
representative symptom is selecting existing text and typing `안녕하세요`, but
the final text becomes only `요`.

The issue was first defined as an InputMethodKit replacement-range policy bug:
the input method repeatedly trusted a stale non-collapsed `selectedRange()` from
the client and passed it back as `insertText(_:replacementRange:)`'s replacement
range. If the host kept reporting that old selection after the first
replacement, each subsequent commit replaced the previous commit, so only the
last unit remained.

This is not a `contenteditable` problem by itself. `contenteditable` is a useful
test surface, but the necessary condition is stale or restored host selection
state.

## Fix Status

The current fix has two parts:

- Ordinary committed text insertion uses `NSRange(location: NSNotFound,
  length: 0)` instead of reusing `selectedRange()`.
- When a committed syllable is immediately followed by a new marked syllable,
  the next marked-text placement is derived from the active `markedRange()` plus
  the committed UTF-16 length, not from a restored host selection.

The strong Chrome fixture now passes with installed `hisle 0.1.2-debug`,
build `5`, and runtime policy
`current-selection-nsnotfound+marked-continuation`.

The later Confluence cursor-jump fix extends this same policy family to
`current-selection-nsnotfound+owned-post-insert-caret`; the selected-range
behavior described here is still part of the current policy.

## User-Visible Shape

Observed failure family:

- User selects existing text in a browser or editor.
- User starts typing more than one commit unit.
- The first committed unit appears.
- Subsequent units replace the previous visible unit.
- Final value contains only the last unit.

Examples from the same family:

- Select text, type `안녕하세요`, final value is `요`.
- Type `1`, select it, type `23456789`, final value is `9`.
- In `가나다라마바사`, select `라`, type `123`, final value can become
  `가나다3마바사`.

The issue does not require Hangul composition. Number and Roman input can expose
the same selected-range failure shape.

## Common Preconditions

- A non-collapsed selection exists before input begins. It can come from drag
  selection, Shift+arrow selection, Command+A, or double-click word selection.
- The input sequence contains more than one commit unit.
- The host/client reports or restores a non-collapsed selection after the first
  replacement instead of reporting the collapsed caret after inserted text.
- The input method maps that stale `selectedRange()` into a document
  replacement range for later commits.

## Historical Hisle Risk Point

The relevant code is in `hisle/InputMethod/InputController.swift`.

Before the fix, `replacementRange(for:)` read both `selectedRange()` and
`markedRange()` from the `IMKTextInput` client. It returned `selectedRange` in
two important cases:

- marked text existed, but the selected range was considered inconsistent with
  the marked range and `selectedRange.length > 0`;
- no marked text existed and `selectedRange.length > 0`.

That meant a host that reported stale selection state could cause `hisle` to
send the stale selected document range back to the host on every commit.

The pure Hangul engine in `hisle-core` is not the suspected source. The bug is
in the IMK client range policy around committed text insertion.

## Local Reproduction

The reproduction is prepared under the Chrome IME diagnostics tooling.

## GUI Smoke Test Verification

Executed on 2026-06-27 10:26-10:27 KST:

```sh
nix develop --command -- make gui-smoke-test
```

Result: passed with exit status 0.

Evidence from the run:

- `hisle-core-spec-check` passed 524 checks.
- Debug app was built and installed to
  `~/Library/Input Methods/hisle.app`.
- Runtime identity showed `hisle 0.1.2-debug`, build `5`, bundle
  `/Users/kia2964158/Library/Input Methods/hisle.app`, and replacement policy
  `current-selection-nsnotfound+marked-continuation`.
- The bundled CLI mode checks passed for initial Roman mode, right Shift
  Hangul mode, Escape Roman mode, left Shift Roman mode, and input-source
  round-trip Roman reset.
- Command+representative `D` save routing passed in both Hangul and Roman
  phases.
- Final saved Sublime Text content was exactly ``f`의f어ㅜff``.

The run printed the known Xcode CoreSimulator and AppIntents metadata warnings,
but the build, install, scripted GUI sequence, CLI checks, and saved-content
assertions all passed.

Stale selected-range model:

```sh
env \
  HISLE_CHROME_SCENARIO=stale-selection-annyeonghaseyo \
  RUN_ID=stale-selection-annyeonghaseyo \
  nix develop .#browser --command -- nu tools/chrome_ime_repro.nu
```

Fixed result:

- Target: `contenteditable`
- Initial text: `가나다라마바사`
- Input sequence: `안녕하세요`
- Expected value: `안녕하세요`
- Actual value observed: `안녕하세요`
- Artifact directory:
  `build/chrome-ime/fix-014-stale-continuation`

Control case with the same contenteditable surface but without stale selection
restoration:

```sh
env \
  HISLE_CHROME_TARGET=contenteditable \
  HISLE_CHROME_SCENARIO=selected-range-annyeonghaseyo \
  HISLE_CHROME_INITIAL_TEXT='가나다라마바사' \
  HISLE_CHROME_INITIAL_SELECTION='0:7' \
  EXPECTED_VALUE='안녕하세요' \
  RUN_ID=fix-014-selected-range-control \
  nix develop .#browser --command -- nu tools/chrome_ime_repro.nu
```

Control result:

- Actual value observed: `안녕하세요`
- Artifact directory:
  `build/chrome-ime/fix-014-selected-range-control`

This confirms that contenteditable alone is not sufficient. The failure appears
when stale selection state is part of the environment.

## Reproduction Fixture Caveat

The current stale fixture intentionally restores the DOM selection after each
composition end. This is a strong model of the stale host-selection condition.
It is useful for reproducing the visible symptom, but it may be stronger than
the real Chromium/Electron issue where `selectedRange()` reported through IMK
can be stale while the host's effective insertion point has already moved.

When validating this family, inspect both the GUI artifact and the IMK client
range trace. The fixed trace should show ordinary commit insertion avoiding
`selectedRange()` and marked continuation placement advancing as `{1,0}`,
`{2,0}`, `{3,0}`, and `{4,0}` for the `안녕하세요` sequence.

## Gureum Reference

Gureum saw a very similar Chromium/Electron selected-range family:

- Gureum issue family included selected text being repeatedly replaced in
  Chrome, Whale, Figma, VSCode, Sublime, GitHub issue pages, and other
  Chromium/Electron/custom editor surfaces.
- PR #855 removed a fallback that re-read `sender.selectedRange()` when the
  current commit range had length 0.
- The follow-up commit settled the empty replacement range as
  `NSRange(location: NSNotFound, length: 0)`.

References:

- https://github.com/gureum/gureum/commit/e2de65998982a4891bf9763a5772b4c5042b70f5
- https://github.com/gureum/gureum/commit/548b740fcc1683ceeb4d068a7e0a0a5760dab757
- https://github.com/gureum/gureum/pull/855

Apple's IMK documentation also states that text inserted at the current
selection should use an `NSNotFound` replacement range rather than an explicit
document range:

- https://leopard-adc.pepas.com/documentation/Cocoa/Reference/IMKTextInput_Protocol/IMKTextInput_Protocol.pdf
