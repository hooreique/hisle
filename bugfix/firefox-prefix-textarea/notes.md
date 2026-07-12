# Firefox Prefix Textarea Notes

## Definition

Observed on 2026-07-05: in Firefox, with a `<textarea>` seeded with `foo bar`
and the caret at offset 0, typing Hangul or Hangul-mode punctuation near the
front can move later composition before earlier committed text. A representative
automated run produced `f의f어ㅜf\`foo bar` instead of
`f\`의f어ㅜffoo bar`.

The user-facing variant is typing repeated `안녕` words before existing textarea
text: new composition should stay linear at the visible caret, producing
`안녕 안녕...` before `foo bar`, not drifting into the existing suffix.

## Cause

Firefox can report a stale collapsed `selectedRange()` immediately after
`insertText(_:replacementRange:)` with the current-selection `NSNotFound`
sentinel. `hisle` recorded that stale range as an owned insertion point even
when the committed text was plain Roman text or Hangul-mode standalone
punctuation with no active marked text. The next marked-text update then used
that stale owned insertion range and started before the previous committed
character.

A later manual Firefox textarea repro showed the same risk after active Hangul
composition commits during fast input. The broad Confluence fix trusted the
post-commit collapsed `selectedRange()` after every active composition commit.
That is still needed when the host's pre-commit selection is inconsistent with
`hisle`'s owned marked range, but Firefox can transiently report a post-commit
range ahead of the intended caret when the pre-commit selection was already
consistent with the owned range.

## Fix

Only composition commits are allowed to update the owned post-commit insertion
range. Plain committed text with no active marked text now clears the tracker
instead of creating or preserving an owned insertion range.

For active composition commits, `hisle` now trusts the post-commit collapsed
`selectedRange()` only when the pre-commit host selection was inconsistent with
the owned replacement range. Otherwise it continues from the owned replacement
range plus committed UTF-16 length.

Runtime identity for the verified debug build:

```text
hisle 0.1.11-debug, build 14
replacementPolicy=current-selection-nsnotfound+conditional-postcommit-caret
bundle=/Users/kia2964158/Library/Input Methods/hisle.app
```

## Verification

The failing Firefox prefix fixture now passes:

```sh
env HISLE_FIREFOX_INITIAL_TEXT='foo bar' HISLE_FIREFOX_INITIAL_CARET='0' HISLE_FIREFOX_SKIP_FOCUS_CLICK=1 EXPECTED_VALUE='f`의f어ㅜffoo bar' RUN_ID='firefox-prefix-standard-build14' nix develop .#browser --command -- make firefox-ime-repro
```

The old `annyeong-words` browser fixture covered `안 녕 안 녕`, which was too
weak for the real user-facing `안녕` word-repeat case:

```sh
env HISLE_FIREFOX_SCENARIO='annyeong-words' HISLE_FIREFOX_TARGET='textarea' HISLE_FIREFOX_INITIAL_TEXT='foo bar' HISLE_FIREFOX_INITIAL_CARET='0' HISLE_FIREFOX_SKIP_FOCUS_CLICK=1 EXPECTED_VALUE='안 녕 안 녕foo bar' RUN_ID='firefox-prefix-annyeong-words-build14-seq' nix develop .#browser --command -- nu tools/firefox_ime_repro.nu
```

The corrected fixture is `annyeong-word-repeats`:

```sh
env HISLE_FIREFOX_SCENARIO='annyeong-word-repeats' HISLE_FIREFOX_TARGET='textarea' HISLE_FIREFOX_INITIAL_TEXT='foo bar' HISLE_FIREFOX_INITIAL_CARET='0' HISLE_FIREFOX_SKIP_FOCUS_CLICK=1 EXPECTED_VALUE='안녕 안녕 안녕 안녕foo bar' RUN_ID='firefox-prefix-annyeong-word-repeats-final' nix develop .#browser --command -- nu tools/firefox_ime_repro.nu
```

Additional checks:

```sh
env HISLE_CHROME_SCENARIO='stale-selection-annyeonghaseyo' RUN_ID='chrome-stale-selection-final' nix develop .#browser --command -- nu tools/chrome_ime_repro.nu
nix develop --command -- make swiftlint
nix develop --command -- make gui-smoke-test
```

## Final Integration Recheck

Build 29 retained the Firefox prefix fix after the state-safe deferred-boundary,
strict-selection-consistency, and plain-commit-fast-path follow-ups. The
`annyeong-word-repeats` textarea regression produced exactly
`안녕 안녕 안녕 안녕foo bar`.

Runtime: `hisle 0.1.14-debug`, core `0.1.1`, build `29`.
Artifact:
`build/firefox-ime/firefox-annyeong-repeats-final-integration-20260713-0623/`.
