# Firefox Prefix Textarea Notes

## Definition

Observed on 2026-07-05: in Firefox, with a `<textarea>` seeded with `foo bar`
and the caret at offset 0, typing Hangul or Hangul-mode punctuation near the
front can move later composition before earlier committed text. A representative
automated run produced `f의f어ㅜf\`foo bar` instead of
`f\`의f어ㅜffoo bar`.

The user-facing variant is typing `안 녕 안 녕` before existing textarea text:
new composition should stay linear at the visible caret, producing the typed
Hangul text before `foo bar`.

## Cause

Firefox can report a stale collapsed `selectedRange()` immediately after
`insertText(_:replacementRange:)` with the current-selection `NSNotFound`
sentinel. `hisle` recorded that stale range as an owned insertion point even
when the committed text was plain Roman text or Hangul-mode standalone
punctuation with no active marked text. The next marked-text update then used
that stale owned insertion range and started before the previous committed
character.

## Fix

Only composition commits are allowed to update the owned post-commit insertion
range. Plain committed text with no active marked text now clears the tracker
instead of creating or preserving an owned insertion range.

Runtime identity for the verified debug build:

```text
hisle 0.1.10-debug, build 14
replacementPolicy=current-selection-nsnotfound+owned-composition-continuation
bundle=/Users/kia2964158/Library/Input Methods/hisle.app
```

## Verification

The failing Firefox prefix fixture now passes:

```sh
env HISLE_FIREFOX_INITIAL_TEXT='foo bar' HISLE_FIREFOX_INITIAL_CARET='0' HISLE_FIREFOX_SKIP_FOCUS_CLICK=1 EXPECTED_VALUE='f`의f어ㅜffoo bar' RUN_ID='firefox-prefix-standard-build14' nix develop .#browser --command -- make firefox-ime-repro
```

The user-facing `안 녕 안 녕` prefix scenario is covered by the new
`annyeong-words` browser fixture:

```sh
env HISLE_FIREFOX_SCENARIO='annyeong-words' HISLE_FIREFOX_TARGET='textarea' HISLE_FIREFOX_INITIAL_TEXT='foo bar' HISLE_FIREFOX_INITIAL_CARET='0' HISLE_FIREFOX_SKIP_FOCUS_CLICK=1 EXPECTED_VALUE='안 녕 안 녕foo bar' RUN_ID='firefox-prefix-annyeong-words-build14-seq' nix develop .#browser --command -- nu tools/firefox_ime_repro.nu
```

Additional checks:

```sh
env HISLE_CHROME_SCENARIO='stale-selection-annyeonghaseyo' RUN_ID='chrome-stale-selection-build14-seq' nix develop .#browser --command -- nu tools/chrome_ime_repro.nu
nix develop --command -- make swiftlint
nix develop --command -- make version-check
nix develop --command -- make gui-smoke-test
```
