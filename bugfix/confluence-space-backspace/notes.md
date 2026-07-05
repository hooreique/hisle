# Confluence Space Backspace Notes

## Definition

Observed on 2026-07-06 in a Confluence live page: with existing text such as
`foo bar` and the caret after `foo`, typing `안녕 ` in Hangul mode inserts the
space after `녕`, but the visible caret can remain immediately after `녕`.
Typing another Hangul word still continues after the space, producing the
expected final text, because `hisle`'s owned insertion range is already after
the inserted space. Pressing Backspace immediately after `안녕 ` is wrong:
Confluence deletes `녕` instead of deleting the just-inserted space.

## Cause

The previous Confluence cursor-jump fix intentionally kept an owned insertion
range across active composition commits so that the next marked-text update did
not follow stale Confluence selections. For a whitespace `FlushThenEmit`
boundary, `hisle-core` emits the active composition and the whitespace as one
committed string, for example `녕 `. `hisle` inserted that string through the
owned marked-text replacement range and advanced its internal insertion range to
after the space.

That preserved the next marked-text start, but it did not force Confluence's
real DOM selection to move after the trailing whitespace. A following marked
text update used the owned range and therefore appeared in the right place. A
following host-forwarded Backspace used Confluence's real selection and deleted
the preceding Hangul syllable.

## Fix

When active Hangul marked text is closed by a whitespace `FlushThenEmit`
boundary, split the IMK host operations:

- commit the active composition through the owned marked-text replacement range
- insert the whitespace separately through the current-selection sentinel
- advance the owned insertion range by the whitespace length for the next
  marked-text update

This keeps the existing Confluence owned-range continuation while giving the
host editor a plain whitespace insertion that moves its own caret before a
later Backspace. The rule is limited to active composition boundaries and does
not revive owned ranges for ordinary plain commits with no active marked text,
which was the Firefox prefix regression.

Runtime identity for this policy should include:

```text
replacementPolicy=current-selection-nsnotfound+split-boundary+conditional-postcommit-caret
```

## Verification

Runtime identity from the installed debug build:

```text
hisle 0.1.12-debug, build 16
replacementPolicy=current-selection-nsnotfound+split-boundary+conditional-postcommit-caret
bundle=/Users/kia2964158/Library/Input Methods/hisle.app
```

Static and smoke checks passed:

```sh
nix develop --command -- make swiftlint
nix develop --command -- make gui-smoke-test
nix develop --command -- make version-check
```

Firefox prefix regression check passed:

```sh
env HISLE_FIREFOX_SCENARIO='annyeong-word-repeats' HISLE_FIREFOX_TARGET='textarea' HISLE_FIREFOX_INITIAL_TEXT='foo bar' HISLE_FIREFOX_INITIAL_CARET='0' HISLE_FIREFOX_SKIP_FOCUS_CLICK=1 EXPECTED_VALUE='안녕 안녕 안녕 안녕foo bar' RUN_ID='firefox-annyeong-repeats-after-space-backspace-fix' nix develop .#browser --command -- nu tools/firefox_ime_repro.nu
```

Artifact:

```text
build/firefox-ime/firefox-annyeong-repeats-after-space-backspace-fix/
matches_expected_value: true
actual_value: 안녕 안녕 안녕 안녕foo bar
```

The new Confluence live Backspace repro passed:

```sh
env HISLE_ATLASSIAN_SCENARIO=annyeong-space-backspace HISLE_ATLASSIAN_INITIAL_CARET_OFFSET=middle RUN_ID=confluence-space-backspace-fix nix develop .#browser --command -- nu tools/atlassian_confluence_repro.nu
```

Artifact:

```text
local/atlassian/runs/confluence-space-backspace-fix/
matches_expected_text: true
matches_expected_full_text: true
expected_text: 안녕
initial_caret_offset: 955
```

The existing Confluence middle-insertion multi-word repro also passed after
reusing the still-open Chrome session from the previous run:

```sh
env HISLE_ATLASSIAN_REUSE_CHROME=1 CHROME_REMOTE_DEBUGGING_PORT=57299 HISLE_ATLASSIAN_SCENARIO='annyeonghaseyo-words' HISLE_ATLASSIAN_WORD_COUNT='3' HISLE_ATLASSIAN_EXPECTED_TEXT='안녕하세요 안녕하세요 안녕하세요' HISLE_ATLASSIAN_INITIAL_CARET_OFFSET='middle' RUN_ID='confluence-words-middle-after-space-backspace-fix-reuse' nix develop .#browser --command -- nu tools/atlassian_confluence_repro.nu
```

Artifact:

```text
local/atlassian/runs/confluence-words-middle-after-space-backspace-fix-reuse/
matches_expected_text: true
matches_expected_full_text: true
expected_text: 안녕하세요 안녕하세요 안녕하세요
initial_caret_offset: 956
```

Two earlier attempts to run the same multi-word repro with a fresh Chrome port
failed before observer readiness because the previous normal Chrome profile
session was still running on remote debugging port `57299`; the failure was at
Chrome CDP startup, before the input-method driver ran.
```
