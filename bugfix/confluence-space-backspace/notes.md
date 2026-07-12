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

A later attempt split the composition commit and whitespace insertion
synchronously. That still failed in the exact `foo bar` middle-insertion case:
Chrome/Confluence accepted the whitespace insertion, then its composition-end
event restored the DOM selection to the position after `녕` and before the
space. The root failure was therefore the Space key leaving the real caret
before the just-inserted whitespace; Backspace deleting `녕` was only the next
visible symptom.

## Fix

When active Hangul marked text is closed by a whitespace `FlushThenEmit`
boundary, split the IMK host operations:

- commit the active composition through the owned marked-text replacement range
- schedule the whitespace for the next main-queue turn
- insert the whitespace through the current-selection sentinel after the host's
  composition-end selection update has completed
- advance the owned insertion range by the whitespace length for the next
  marked-text update

This keeps the existing Confluence owned-range continuation while making the
plain whitespace insertion occur after Chrome/Confluence has finished restoring
selection for the ended composition. The rule is limited to active composition
boundaries and does not revive owned ranges for ordinary plain commits with no
active marked text, which was the Firefox prefix regression.

Runtime identity for this policy should include:

```text
replacementPolicy=current-selection-nsnotfound+split-boundary+deferred-boundary+conditional-postcommit-caret
```

## Verification

Runtime identity from the installed debug build:

```text
hisle 0.1.14-debug, build 26
replacementPolicy=current-selection-nsnotfound+split-boundary+deferred-boundary+conditional-postcommit-caret
bundle=/Users/kia2964158/Library/Input Methods/hisle.app
```

The exact live Confluence repro passed:

```sh
env HISLE_ATLASSIAN_REUSE_CHROME=1 CHROME_REMOTE_DEBUGGING_PORT=55934 HISLE_ATLASSIAN_SCENARIO=foo-bar-annyeong-space-backspace HISLE_ATLASSIAN_INITIAL_CARET_OFFSET=middle RUN_ID=confluence-foo-bar-space-deferred-boundary-reuse-20260706 nix develop .#browser --command -- nu tools/atlassian_confluence_repro.nu
```

Artifact:

```text
local/atlassian/runs/confluence-foo-bar-space-deferred-boundary-reuse-20260706/
matches_expected_text: true
matches_expected_full_text: true
expected_text: foo안녕 bar
```

Representative DOM event order from that run:

```text
compositionend selection_start=161
space input selection_start=162
Backspace keydown selection_start=162
```

Additional checks passed:

```sh
nix develop --command -- make swiftlint
nix develop .#browser --command -- node --check tools/chrome-ime/atlassian_observer.mjs
nix develop .#browser --command -- nu --ide-check 0 tools/atlassian_confluence_repro.nu
nix develop --command -- make version-check
env HISLE_FIREFOX_SCENARIO='annyeong-word-repeats' HISLE_FIREFOX_TARGET='textarea' HISLE_FIREFOX_INITIAL_TEXT='foo bar' HISLE_FIREFOX_INITIAL_CARET='0' HISLE_FIREFOX_SKIP_FOCUS_CLICK=1 EXPECTED_VALUE='안녕 안녕 안녕 안녕foo bar' RUN_ID='firefox-annyeong-repeats-after-deferred-boundary-fix-20260706' nix develop .#browser --command -- nu tools/firefox_ime_repro.nu
nix develop --command -- make gui-smoke-test
```

## Deferred Boundary State-Safety Follow-up

The first deferred implementation captured an IMK client in an untracked main
queue callback. A later input or lifecycle transition could run first, after
which the callback could clear newer marked state, advance a newer owned range,
or outlive the session that accepted the whitespace. Multi-scalar fallback text
could also overtake the deferred boundary in the original call stack.

The follow-up binds each accepted boundary to its exact client, active
editing-context generation, range snapshot, and ticket in a FIFO queue. Every
later input and lifecycle boundary drains queued work before changing state;
stale scheduled tickets then do nothing. Remaining scalars from the same
fallback event stay with the boundary ticket and resume through the Hangul path
after insertion, independent of later shared-mode changes. A continuation is
folded through an engine copy before its next host mutation, and its aggregate
commit/marked output is owned by a phase-tracked intent so lifecycle or range
query reentry can finish it exactly once. Deferred delivery no longer clears
`markedText`.

The deterministic check covers next-turn delivery, distinct whitespace FIFO
ordering, zero-delay input, Backspace/navigation, mode and focus changes,
separate client sessions, deactivation, stale tickets, reentrant host phases,
and the `foo bar` middle-insertion result:

```sh
nix develop --command -- make deferred-boundary-check
nix develop --command -- make swiftlint
nix develop --command -- make build
```

The follow-up was verified with the installed debug app and the browser
regressions on 2026-07-13 KST:

```text
hisle 0.1.14-debug, build 29
replacementPolicy=current-selection-nsnotfound+split-boundary+state-safe-deferred-boundary+plain-commit-fast-path+strict-selection-consistency+conditional-postcommit-caret

GUI smoke test: passed
Firefox annyeong-word-repeats: `안녕 안녕 안녕 안녕foo bar` (exact match)
Chrome stale-selection-annyeonghaseyo: `안녕하세요` (exact match)
Confluence foo-bar-annyeong-space-backspace: `foo안녕 bar` (exact delta and full-text match)
Confluence selectionchange events: 21
Non-null payload counts: key 40, code 40, data 44, inputType 34, isComposing 74
Confluence observer page errors: 0
```

Browser artifacts:

```text
build/firefox-ime/firefox-annyeong-repeats-final-integration-20260713-0623/
build/chrome-ime/chrome-stale-selection-final-integration-20260713-0622/
local/atlassian/runs/confluence-final-integration-reuse-20260713-0625/
```
