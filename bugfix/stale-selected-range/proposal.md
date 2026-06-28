# Stale Selected Range Replacement Proposal

## Goal

Fix the selected-range replacement policy so that stale host `selectedRange()`
cannot be reused as the document replacement range for every committed unit.

The expected user-visible result is that selecting text and typing a multi-unit
sequence replaces the selection once, then continues inserting after the newly
inserted text. For example, typing `안녕하세요` should leave `안녕하세요`, not
only `요`.

## Principle

Use explicit document replacement ranges only for ranges owned by the active
composition, especially a valid `markedRange()`.

For ordinary committed text insertion, ask the host to insert at the current
selection by passing the `NSNotFound` sentinel range. Do not turn
`client.selectedRange()` into an explicit replacement range on every commit.

For commit-plus-new-marked-text transitions, preserve the input method's own
composition position. If a committed syllable replaces an active `markedRange()`
and the same key event starts the next marked syllable, place that next marked
text at `markedRange.location + committedText.utf16.count`. Do not let a
composition-end handler or stale host selection move the new marked text back to
the old selection.

This matches the practical direction from Gureum's Chromium compatibility fix:
remove the fallback that re-reads `sender.selectedRange()` for commit
replacement and use `NSRange(location: NSNotFound, length: 0)` for current
selection insertion.

## Proposed Code Change

Change `hisle/InputMethod/InputController.swift` only. Keep `hisle-core`
unchanged.

Introduce a helper for the current-selection sentinel:

```swift
private var currentSelectionReplacementRange: NSRange {
    NSRange(location: NSNotFound, length: 0)
}
```

Then reduce `replacementRange(for:)` to this policy:

```swift
private func replacementRange(for client: IMKTextInput) -> NSRange {
    let selectedRange = client.selectedRange()
    let markedRange = client.markedRange()

    if hasMarkedText, markedRange.location != NSNotFound, markedRange.length > 0 {
#if DEBUG
        traceReplacementRange(
            markedRange,
            selectedRange: selectedRange,
            markedRange: markedRange,
            reason: "marked"
        )
#endif
        return markedRange
    }

    let currentSelection = NSRange(location: NSNotFound, length: 0)
#if DEBUG
    traceReplacementRange(
        currentSelection,
        selectedRange: selectedRange,
        markedRange: markedRange,
        reason: "current-selection"
    )
#endif
    return currentSelection
}
```

Important details:

- Do not return `selectedRange` just because `selectedRange.length > 0`.
- Do not use `selectedRange` as a fallback when `markedRange` and
  `selectedRange` disagree.
- Keep reading `selectedRange` for debug tracing, because it is useful evidence
  when diagnosing host/client range bugs.
- Keep using `markedRange` for active marked text replacement, because that
  range belongs to the active inline composition.
- For immediate marked-text continuation after a commit, use the just-replaced
  `markedRange` and committed UTF-16 length to compute a zero-length
  replacement range for `updateComposition()`.
- Keep the change app-agnostic. Avoid Chrome/Electron/contenteditable-specific
  branching.

## Why This Is Correct

`selectedRange()` is host state. In the failing class, that state can be stale
or repeatedly restored by the host/editor. Reusing it as an explicit document
replacement range gives the stale state authority over every later commit.

`markedRange()` is different: while `hasMarkedText` is true, it names the active
inline composition that the input method owns. Replacing that range is the
normal IMK commit path.

For non-marked committed insertion, `NSRange(location: NSNotFound, length: 0)`
delegates "insert at the current selection" to the host without freezing a
possibly stale document range inside the input method.

For marked continuation, the active `markedRange()` is still input-method-owned
state. Advancing from that range by the committed text length keeps the next
marked syllable after the committed syllable even if the host restores a stale
selection during `compositionend`.

## Verification Plan

1. Install the debug input method.

```sh
nix develop --command -- make install-debug
```

2. Run the ordinary GUI smoke test.

```sh
nix develop --command -- make gui-smoke-test
```

3. Run the contenteditable selected-range control.

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

4. Run the stale selected-range scenario with the fixed expected value.

```sh
env \
  HISLE_CHROME_SCENARIO=stale-selection-annyeonghaseyo \
  RUN_ID=stale-selection-annyeonghaseyo-fixed \
  nix develop .#browser --command -- nu tools/chrome_ime_repro.nu
```

5. Inspect `runtime-identity.log` and `ime.log` for the fixed run. The runtime
   identity should show the installed app version and replacement policy, and
   the range trace should show marked continuation placement advancing through
   `{1,0}`, `{2,0}`, `{3,0}`, and `{4,0}`.

## Expected Patch Shape

The minimal implementation should touch:

- `hisle/InputMethod/InputController.swift`
- `hisle/Config/HisleVersion.xcconfig`, when producing a new installed debug
  build for verification
- `tools/chrome_ime_repro.nu`, if the stale scenario default expected value is
  promoted from symptom reproduction to regression verification
- `docs/testing.md`, only if command expectations or scenario names change

The implementation should not touch:

- `hisle-core/`
- keyboard layout data
- input mode selection policy
- app-specific browser detection

## Regression Risks

- Some native text clients may have relied on explicit selected-range
  replacement. The IMK contract says current-selection insertion should be
  represented with `NSNotFound`, so this should be the safer default.
- If a client reports a valid `markedRange()` incorrectly, marked-text commit
  can still be affected. Keep the existing debug traces around
  `selectedRange`, `markedRange`, `hasMarkedText`, and replacement reason.
- Explicit marked continuation placement is intentionally narrow: it is used
  only after the input method has just replaced an active marked range and the
  same output starts the next marked text. Ordinary committed insertion still
  uses `NSNotFound,0`.

## Related References

- Gureum Chromium compatibility fix:
  https://github.com/gureum/gureum/commit/e2de65998982a4891bf9763a5772b4c5042b70f5
- Gureum follow-up for `NSNotFound, 0`:
  https://github.com/gureum/gureum/commit/548b740fcc1683ceeb4d068a7e0a0a5760dab757
- Gureum PR #855:
  https://github.com/gureum/gureum/pull/855
- IMKTextInput protocol reference:
  https://leopard-adc.pepas.com/documentation/Cocoa/Reference/IMKTextInput_Protocol/IMKTextInput_Protocol.pdf
