# Confluence Cursor Jump Fix Proposal

Status: implemented. See `report.md` for the final fix and verification
evidence.

## Goal

Make Confluence Cloud editing behave like ordinary text editing for Hangul
input:

- Typing several Hangul words should insert text linearly at the visible caret.
- Composition boundaries should not let a stale or editor-restored host
  selection move the next marked syllable to an earlier or later document
  position.
- Fresh app/client/input-source activation should continue to initialize Roman
  mode as documented in `docs/input-modes.md`.

## Constraints

- Keep `hisle-core/` unchanged unless a later repro proves the automaton is
  involved.
- Do not add Confluence-specific app detection to the input method as the first
  fix. Prefer a general IMK range/state policy that also makes sense for other
  ProseMirror, Chromium, or custom editor surfaces.
- Preserve the intended input-mode policy from `docs/input-modes.md`: switching
  between host apps, activating a new IMK text client/session, or switching away
  to another input source and back to `hisle` should enter Roman mode.
- Keep generated traces and screenshots under `local/atlassian/runs/` or
  `build/`, not in tracked docs.

## Reproduction Commands

Multi-word cursor jump:

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

Roman-initialization policy check:

```sh
env \
  HISLE_ATLASSIAN_REUSE_CHROME=1 \
  CHROME_REMOTE_DEBUGGING_PORT=57325 \
  HISLE_ATLASSIAN_HANGUL_BEFORE_EDITOR_CLICK=1 \
  RUN_ID=hangul-before-editor-click-trace \
  nix develop .#browser --command -- nu tools/atlassian_confluence_repro.nu
```

This scenario should verify Roman mode after editor focus, then select Hangul
again before typing.

Use `HISLE_ATLASSIAN_ALLOW_MISMATCH=1` when the goal is to keep a failing run
successful for artifact capture.

## Next Instrumentation Step

Capture a multi-word failure with a stable editor focus and IMK client range
trace enabled:

```sh
defaults write hooreique.inputmethod.hisle traceClientRanges -bool YES

env \
  HISLE_ATLASSIAN_REUSE_CHROME=1 \
  CHROME_REMOTE_DEBUGGING_PORT=57325 \
  HISLE_ATLASSIAN_SCENARIO=annyeonghaseyo-words \
  HISLE_ATLASSIAN_WORD_COUNT=3 \
  HISLE_ATLASSIAN_EXPECTED_TEXT='안녕하세요 안녕하세요 안녕하세요' \
  HISLE_ATLASSIAN_ALLOW_MISMATCH=1 \
  RUN_ID=words-three-range-trace \
  nix develop .#browser --command -- nu tools/atlassian_confluence_repro.nu

defaults write hooreique.inputmethod.hisle traceClientRanges -bool NO
```

Inspect:

- `local/atlassian/runs/words-three-range-trace/dom-events.jsonl`
- `local/atlassian/runs/words-three-range-trace/final-state.json`
- `local/atlassian/runs/words-three-range-trace/ime.log`
- `local/atlassian/runs/words-three-range-trace/keys.jsonl`

Needed evidence:

- `selectedRange()` and `markedRange()` before each key.
- replacement range selected for `insertText`.
- replacement range selected by `updateComposition()`.
- DOM selection before and after `compositionend` and the next
  `compositionstart`.

## Candidate Fix Directions

### 1. Preserve Composition Continuation Across Host Selection Drift

The multi-word corruption suggests Confluence can move selection between
composition units. The current range policy protects the immediate
commit-plus-marked continuation path, but not every composition boundary.

Possible directions:

- Track an input-method-owned logical insertion range after each successful
  commit/update while a Hangul typing burst is active.
- Use that range for the next marked text when the host reports a selection
  jump without a corresponding input-method-owned navigation, mouse, or
  explicit selection action.
- Clear that tracked range on host action keys, mouse down, explicit
  deactivation, mode changes, or any input that should legitimately move the
  caret.

Risk: if the user or host genuinely moves the caret, over-preserving the old
composition point would insert in the wrong place. The fix needs conservative
invalidation.

### 2. Strengthen Diagnostics Before Patching

Before changing range behavior, improve the repro artifacts enough to separate
the host/client and input-method layers:

- Add scenario metadata to final-state.
- Include `selection_anchor` and `selection_focus` in anomaly samples.
- Capture compact `client-range` excerpts into a dedicated artifact or ensure
  `ime.log` starts before editor focus and right Shift in all Confluence
  scenarios.
- Consider a Confluence fixture mode that clicks a known text offset instead
  of an estimated editor midpoint, because the initial click itself currently
  shows a large selection jump.

This diagnostic work is low-risk and should make the actual fix easier to
review.

## Verification Plan

After a candidate patch:

1. Run the app-level lint/build checks.

```sh
nix develop --command -- make swiftlint
nix develop --command -- make gui-smoke-test
```

2. Re-run the existing browser fixture to guard the stale selected-range fix.

```sh
env \
  HISLE_CHROME_SCENARIO=stale-selection-annyeonghaseyo \
  RUN_ID=stale-selection-annyeonghaseyo-after-confluence-fix \
  nix develop .#browser --command -- nu tools/chrome_ime_repro.nu
```

3. Re-run the Confluence multi-word scenario.

```sh
env \
  HISLE_ATLASSIAN_REUSE_CHROME=1 \
  CHROME_REMOTE_DEBUGGING_PORT=<port> \
  HISLE_ATLASSIAN_SCENARIO=annyeonghaseyo-words \
  HISLE_ATLASSIAN_WORD_COUNT=3 \
  HISLE_ATLASSIAN_EXPECTED_TEXT='안녕하세요 안녕하세요 안녕하세요' \
  RUN_ID=words-three-after-fix \
  nix develop .#browser --command -- nu tools/atlassian_confluence_repro.nu
```

4. Re-run the Roman-initialization policy check if the patch changes
   input-mode activation behavior.

```sh
env \
  HISLE_ATLASSIAN_REUSE_CHROME=1 \
  CHROME_REMOTE_DEBUGGING_PORT=<port> \
  HISLE_ATLASSIAN_HANGUL_BEFORE_EDITOR_CLICK=1 \
  RUN_ID=hangul-before-editor-click-after-fix \
  nix develop .#browser --command -- nu tools/atlassian_confluence_repro.nu
```

Passing criteria:

- The multi-word final value contains exactly the expected inserted substring.
- `selection_jump_without_value_change_count` and
  `selection_regression_count` no longer show composition-boundary oscillation
  for the typed words.
- The stale selected-range Chrome fixture remains fixed.
- GUI smoke test still passes, including the documented input-source round-trip
  Roman reset.
- The Confluence pre-focus scenario still verifies Roman mode after editor
  focus before selecting Hangul for actual typing.
