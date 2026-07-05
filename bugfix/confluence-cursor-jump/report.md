# Confluence Cursor Jump Report

## Summary

Confluence Cloud's ProseMirror editor can move the effective insertion point
during Hangul composition. In a live Confluence page, typing a few ordinary
Hangul words through `hisle` produces interleaved text instead of the expected
linear text.

This is user-visible as the cursor "jumping around" while editing Confluence:
letters from later syllables appear in earlier positions, and the final text is
corrupted.

This is not suspected to be a `hisle-core` Hangul automaton issue. The same
physical key sequence works in the local Chrome fixture and in the successful
single-word Confluence run. The suspected ownership is the InputMethodKit
integration around Confluence's reported selection and marked range behavior.

## Fix Status

Fixed on 2026-07-05 after rechecking the true middle-insertion case, where
existing text remains after the insertion point. A later same-day Roman-mode
regression showed that applying the owned insertion range to ordinary committed
text was too broad: Confluence can move explicit ranges even when no marked text
is active. The current policy keeps the owned range only for active marked text
and the next marked-text update after a commit.

The new policy keeps using `NSRange(location: NSNotFound, length: 0)` for
ordinary current-selection insertion, including Roman-mode committed text with
no active marked text. It tracks the marked range and collapsed insertion range
created by `hisle`'s own composition updates and commits, then uses those owned
ranges for later marked updates, composition commits, whitespace that flushes an
active composition, and the next marked-text start. It clears the owned range on
mouse down, host-forwarded action keys, mode changes, deactivation, and external
cancel/commit boundaries.

The important middle-insertion correction is that the tracker now prefers a
valid collapsed `selectedRange()` observed immediately after
`insertText(_:replacementRange:)` as the next insertion point. Confluence can
remap IMK coordinates after a commit; continuing by adding the committed length
to the pre-commit replacement range can point back into earlier document
content.

Runtime identity for the verified build:

```text
hisle 0.1.9-debug, build 12
replacementPolicy=current-selection-nsnotfound+owned-marked-continuation
bundle=/Users/kia2964158/Library/Input Methods/hisle.app
```

The representative Confluence middle-insertion multi-word run now passes. This
run sets `HISLE_ATLASSIAN_INITIAL_CARET_OFFSET=middle`, places the caret inside
existing Confluence content, and checks the full expected DOM Range text rather
than only checking whether the expected substring appears somewhere:

```text
Artifact directory: local/atlassian/runs/words-three-owned-post-insert-caret-middle-range/
Expected text: 안녕하세요 안녕하세요 안녕하세요
initial_caret_offset: 81
contains_expected_text: true
matches_expected_full_text: true
matches_expected_text: true
```

The first attempt at an owned-caret fix, build 11 with policy
`current-selection-nsnotfound+owned-caret`, passed an end-biased run but failed
the middle-insertion strict run. That failure was real: after the first commit,
the next composition could still be placed at the wrong position when the
pre-commit replacement coordinate no longer matched Confluence's post-commit
coordinate.

The fixed Hangul trace still shows Confluence reporting shifted client ranges,
but the input method no longer follows those host-selected positions for its
owned marked-text typing burst. Representative IMK decisions from the passing
middle run include:

```text
reason=owned-marked selected={86, 1} marked={9, 1} replacement={9, 1}
after-commit committedLength=1 selected={87, 0}
reason=owned-insertion selected={87, 0} replacement={87, 0}
```

The later Roman-mode regression was captured with no composition events. The
old broad owned-insertion policy turned `foo bar foo bar` into interleaved text
such as `fobar foo bar`, because ordinary committed Roman text was sent to an
explicit range that Confluence had moved. After narrowing the policy, a unique
Roman run produced the expected text contiguously:

```text
Failing artifact: local/atlassian/runs/roman-foo-bar-20260705-2030/
Traced fixed artifact: local/atlassian/runs/roman-text-foo-qux-fixed-20260705-2105/
Current-driver fixed artifact: local/atlassian/runs/roman-text-foo-xyz-fixed-20260705-2125/
Expected text: foo xyz foo xyz
matches_expected_text: true
contains_expected_text: true
composition_event_count: 0
```

Representative fixed Roman IMK decisions use the current-selection sentinel for
each plain committed character:

```text
replacement={9223372036854775807, 0} reason=current-selection
```

Follow-up verification on 2026-07-05 passed the known live Confluence cursor
jump repros with the current debug build:

```text
verify-hangul-words5-end-20260705:
  expected_text: 안녕하세요 안녕하세요 안녕하세요 안녕하세요 안녕하세요
  matches_expected_text: true

verify-hangul-words5-middle-20260705:
  expected_text: 안녕하세요 안녕하세요 안녕하세요 안녕하세요 안녕하세요
  initial_caret_offset: 175
  matches_expected_text: true
  matches_expected_full_text: true

verify-roman-foo-bar-20260705:
  expected_text: foo bar foo bar
  matches_expected_text: true

verify-roman-unique-qwx-20260705:
  expected_text: qwx foo zyx qwx
  matches_expected_text: true
  composition_event_count: 0
```

The follow-up live verification commands were:

```sh
env HISLE_ATLASSIAN_REUSE_CHROME=1 CHROME_REMOTE_DEBUGGING_PORT=60739 HISLE_ATLASSIAN_SCENARIO=annyeonghaseyo-words HISLE_ATLASSIAN_WORD_COUNT=5 HISLE_ATLASSIAN_EXPECTED_TEXT='안녕하세요 안녕하세요 안녕하세요 안녕하세요 안녕하세요' HISLE_ATLASSIAN_KEEP_OPEN=1 RUN_ID=verify-hangul-words5-end-20260705 nix develop .#browser --command -- nu tools/atlassian_confluence_repro.nu
env HISLE_ATLASSIAN_REUSE_CHROME=1 CHROME_REMOTE_DEBUGGING_PORT=60739 HISLE_ATLASSIAN_SCENARIO=annyeonghaseyo-words HISLE_ATLASSIAN_WORD_COUNT=5 HISLE_ATLASSIAN_EXPECTED_TEXT='안녕하세요 안녕하세요 안녕하세요 안녕하세요 안녕하세요' HISLE_ATLASSIAN_INITIAL_CARET_OFFSET=middle HISLE_ATLASSIAN_KEEP_OPEN=1 RUN_ID=verify-hangul-words5-middle-20260705 nix develop .#browser --command -- nu tools/atlassian_confluence_repro.nu
env HISLE_ATLASSIAN_REUSE_CHROME=1 CHROME_REMOTE_DEBUGGING_PORT=60739 HISLE_ATLASSIAN_SCENARIO=roman-foo-bar HISLE_ATLASSIAN_EXPECTED_TEXT='foo bar foo bar' HISLE_ATLASSIAN_KEEP_OPEN=1 RUN_ID=verify-roman-foo-bar-20260705 nix develop .#browser --command -- nu tools/atlassian_confluence_repro.nu
env HISLE_ATLASSIAN_REUSE_CHROME=1 CHROME_REMOTE_DEBUGGING_PORT=60739 HISLE_ATLASSIAN_SCENARIO=roman-text HISLE_ATLASSIAN_ROMAN_TEXT='qwx foo zyx qwx' HISLE_ATLASSIAN_EXPECTED_TEXT='qwx foo zyx qwx' HISLE_ATLASSIAN_KEEP_OPEN=1 RUN_ID=verify-roman-unique-qwx-20260705 nix develop .#browser --command -- nu tools/atlassian_confluence_repro.nu
```

This verifies the known cursor-jump failure modes in the live Confluence page.
It does not claim every possible Confluence editor state is covered.

## Primary Multi-Word Reproduction

Run against a logged-in Confluence Chrome session:

```sh
env \
  HISLE_ATLASSIAN_REUSE_CHROME=1 \
  CHROME_REMOTE_DEBUGGING_PORT=57325 \
  HISLE_ATLASSIAN_SCENARIO=annyeonghaseyo-words \
  HISLE_ATLASSIAN_WORD_COUNT=3 \
  HISLE_ATLASSIAN_EXPECTED_TEXT='안녕하세요 안녕하세요 안녕하세요' \
  RUN_ID=words-three \
  nix develop .#browser --command -- nu tools/atlassian_confluence_repro.nu
```

Artifact directory:

```text
local/atlassian/runs/words-three/
```

Observed final text excerpt:

```text
안안하녕요 안녕하세요 안녕하세요하세녕세요본문2
```

Expected inserted text:

```text
안녕하세요 안녕하세요 안녕하세요
```

Important final-state counters:

- `matches_expected_text: false`
- `contains_expected_text: false`
- `value_changed: true`
- `composition_event_count: 79`
- `input_event_count: 50`
- `beforeinput_event_count: 50`
- `selection_jump_without_value_change_count: 5`
- `selection_regression_count: 176`

The most useful DOM evidence is in
`local/atlassian/runs/words-three/final-state.json` and
`local/atlassian/runs/words-three/dom-events.jsonl`.

Representative cursor jumps with no text-length change:

```text
event              previous selection -> selection  delta
pointerup          23 -> 9              -14
compositionstart   10 -> 14             +4
compositionstart   15 -> 11             -4
compositionstart   12 -> 16             +4
compositionstart   17 -> 13             -4
```

The repeated `compositionstart` jumps are the core symptom for the multi-word
case. They happen at composition boundaries, not as ordinary forward caret
movement after insertion.

## Input-Mode Policy Observation

Selecting Hangul mode before focusing the editor is undone when the Confluence
editor receives focus. This is not a bug in the current policy: `hisle` is
intended to initialize fresh app/client/input-source activation in Roman mode
rather than preserving Hangul mode across contexts.

Run:

```sh
env \
  HISLE_ATLASSIAN_REUSE_CHROME=1 \
  CHROME_REMOTE_DEBUGGING_PORT=57325 \
  HISLE_ATLASSIAN_HANGUL_BEFORE_EDITOR_CLICK=1 \
  RUN_ID=hangul-before-editor-click-trace \
  nix develop .#browser --command -- nu tools/atlassian_confluence_repro.nu
```

Artifact directory:

```text
local/atlassian/runs/hangul-before-editor-click-trace/
```

Driver-observed sequence from the original capture:

```text
Confluence pre-focus initial mode CLI mode verified: roman
Confluence pre-focus right Shift CLI mode verified: hangul
Clicking Confluence editor screen point: (591.5, 573.0)
Atlassian Confluence driver failed: Confluence pre-focus Hangul mode CLI mode
verification failed. Expected "hangul", got "roman".
```

That capture predates the test-harness correction for this policy. The Roman
mode result is expected; the failure was the driver's old expectation.

IMK log evidence:

```text
input mode selected hangul
controller runtime stage=initialized
controller runtime stage=activated
input mode selected roman
```

This aligns with `docs/input-modes.md` and the implementation path where
`setValue(_:forTag:client:)` handles `kTextServiceInputModePropertyTag` by
selecting Roman mode. The observation is useful as a test-harness guardrail:
Confluence cursor-jump repros should select Hangul after the editor has focus.

## Successful Baseline

A single `안녕하세요` typed after the Confluence editor is already focused and
after Hangul mode is selected can pass.

Artifact directory:

```text
local/atlassian/runs/20260705-175941-MW5NGY/
```

The final text contains `안녕하세요`, and `matches_expected_text` was `true`.
This baseline shows that Confluence editing is not universally broken. The
failure appears when multiple Hangul composition units and spaces are typed in
one editing run after Hangul mode is selected for the focused editor.

## Suspected Ownership

Likely files:

- `hisle/InputMethod/InputController.swift`
- `hisle/InputMethod/InputController+Composition.swift`
- `hisle/InputMethod/InputController+KeyHandling.swift`
- `hisle/InputMethod/MarkedTextRangePolicy.swift`
- `hisle/InputMethod/ClientRangeTracer.swift`
- `tools/atlassian_confluence_repro.nu`
- `tools/atlassian_confluence_driver.swift`
- `tools/chrome-ime/atlassian_observer.mjs`

The pure Hangul behavior in `hisle-core/` is not the first suspect.

## Root Cause Notes

1. Confluence/ProseMirror can restore or mutate DOM selection around
   `compositionend` and the next `compositionstart`. If `hisle` asks IMK to
   place new marked text at the host's current selection with `NSNotFound,0`,
   the next marked syllable can follow that moved host selection instead of the
   input method's previous composition continuation point.

2. The older marked-continuation policy only preserved a replacement range
   in narrow commit-plus-new-marked-text transitions inside one engine output.
   It did not preserve an input-method-owned caret across a completed
   syllable, a whitespace commit, and the next composition start when
   Confluence moves selection between those events.

3. The first owned-caret patch still derived some continuation positions from
   the pre-commit replacement range. In middle-of-document Confluence content,
   the client can report a different collapsed caret after the commit. The final
   fix records that post-commit collapsed caret and uses it for the next owned
   marked-text start.

The passing `words-three-owned-post-insert-caret-middle-range` trace confirms
the direction: Confluence can still report different `selectedRange()` and
`markedRange()` values, while an input-method-owned replacement range based on
post-commit caret observation keeps the typed text linear.

## Verification State

Commands run while preparing the reproduction environment:

```sh
nix develop .#browser --command -- node --check tools/chrome-ime/atlassian_observer.mjs
nix develop .#browser --command -- nu --ide-check 100 tools/atlassian_confluence_repro.nu
nix develop .#browser --command -- /usr/bin/xcrun swiftc tools/GuiTestSupport.swift tools/atlassian_confluence_driver.swift -o build/tools/atlassian_confluence_driver.check
nix develop --command -- make swiftlint
git diff --check
```

`make swiftlint` passed with 0 violations after adding the Confluence repro
tools.

The `traceClientRanges` default was temporarily enabled during investigation
and then disabled again:

```sh
defaults write hooreique.inputmethod.hisle traceClientRanges -bool NO
```

Commands run for the fix:

```sh
nix develop --command -- make swiftlint
nix develop --command -- make build
nix develop --command -- make gui-smoke-test
env HISLE_CHROME_SCENARIO=stale-selection-annyeonghaseyo RUN_ID=stale-selection-annyeonghaseyo-owned-post-insert-caret nix develop .#browser --command -- nu tools/chrome_ime_repro.nu
env HISLE_ATLASSIAN_REUSE_CHROME=1 CHROME_REMOTE_DEBUGGING_PORT=57325 HISLE_ATLASSIAN_INITIAL_CARET_OFFSET=middle HISLE_ATLASSIAN_SCENARIO=annyeonghaseyo-words HISLE_ATLASSIAN_WORD_COUNT=3 HISLE_ATLASSIAN_EXPECTED_TEXT='안녕하세요 안녕하세요 안녕하세요' RUN_ID=words-three-owned-post-insert-caret-middle-range nix develop .#browser --command -- nu tools/atlassian_confluence_repro.nu
env HISLE_ATLASSIAN_REUSE_CHROME=1 CHROME_REMOTE_DEBUGGING_PORT=60739 HISLE_ATLASSIAN_SCENARIO=roman-text HISLE_ATLASSIAN_ROMAN_TEXT='foo qux foo qux' HISLE_ATLASSIAN_EXPECTED_TEXT='foo qux foo qux' HISLE_ATLASSIAN_KEEP_OPEN=1 RUN_ID=roman-text-foo-qux-fixed-20260705-2105 nix develop .#browser --command -- nu tools/atlassian_confluence_repro.nu
env HISLE_ATLASSIAN_REUSE_CHROME=1 CHROME_REMOTE_DEBUGGING_PORT=60739 HISLE_ATLASSIAN_SCENARIO=roman-text HISLE_ATLASSIAN_ROMAN_TEXT='foo xyz foo xyz' HISLE_ATLASSIAN_EXPECTED_TEXT='foo xyz foo xyz' HISLE_ATLASSIAN_KEEP_OPEN=1 RUN_ID=roman-text-foo-xyz-fixed-20260705-2125 nix develop .#browser --command -- nu tools/atlassian_confluence_repro.nu
nix develop --command -- make version-check
git diff --check
```

All commands above exited with status 0. The GUI smoke test verified the
documented Roman/Hangul mode transitions, shortcut forwarding, and input-source
round-trip Roman reset. The stale selected-range Chrome fixture still produced
exactly `안녕하세요`. The Confluence run verified full-text equality at a middle
caret position with existing text after the insertion point. The Confluence
Roman-mode run verified that plain committed Roman input stays contiguous in
the editor without composition events.
