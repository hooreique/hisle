# Bug Fixes

This document defines the bug-fix rules that should stay stable across
different kinds of failures. Read it before starting or continuing a bug fix,
then read the owning area document from `AGENTS.md` for the code you expect to
change.

## Required

- Define enough of the bug before making broad changes: observed behavior,
  expected behavior, affected area, and the current hypothesis or unknown.
- For tracked bugs, keep durable notes under `bugfix/<bug-name>/`.
- Use the verification route from `AGENTS.md` for the changed ownership area.
  If the preferred route cannot run locally, record what was run and what is
  still unverified.
- Keep large generated artifacts under `build/` and link to their paths from
  notes instead of copying logs into the repository.
- When an investigation changes the installed app binary, bump
  `CURRENT_PROJECT_VERSION` only. Do not bump `MARKETING_VERSION` for
  investigation builds.

## Flexible

Bug fixes do not all need the same investigation shape. Choose the order and
depth that fit the failure:

- You may start from reproduction, code reading, a reference implementation, a
  targeted patch, or a narrower test.
- Use as many or as few Markdown notes as the investigation needs. File names
  such as `definition.md`, `repro.md`, `plan.md`, `proposal.md`, `report.md`,
  or `notes.md` are conventions, not a required sequence.
- Keep the status vocabulary practical. Phrases such as `fixed`,
  `in progress`, `stuck`, or `needs repro` are enough.
- Tiny, obvious local fixes can be covered by the test, commit, or PR notes
  instead of a separate `bugfix/` record.

## Records

Create a tracked record when a bug is non-trivial, user-visible, recurring, or
likely to span more than one session. Keep one directory under `bugfix/`:

```text
bugfix/<bug-name>/
  *.md
  status
```

Use an intuitive bug name that will still make sense later. Prefer short,
lowercase hyphenated names, but clarity matters more than a strict naming
scheme.

The first note can use any clear file name. Keep it concise, but include enough
for a later maintainer to reconstruct the work:

- observed behavior and expected behavior
- reproduction steps, failing command, or external symptom
- suspected ownership area and likely files or modules
- expected implementation, documentation, and verification shape
- links or paths to generated artifacts instead of large copied logs

Keep the current state in `bugfix/<bug-name>/status`. This file has no
extension and should contain a short phrase such as `in progress`, `fixed`,
`stuck`, or `needs repro`. Update it when the bug's state changes and again
when the fix lands.

## Runtime Version Identity

After changing the installed app binary during investigation, confirm that the
running binary is the one you intended to test. Inspect the
`controller runtime` log entry, or the Chrome IME reproduction's
`build/chrome-ime/<run-id>/runtime-identity.log`, and check that
`buildProfile=` is the expected `debug` or `release`, `build=` matches the
current `CURRENT_PROJECT_VERSION`, `coreVersion=` matches `HisleCore.version`,
`bundle=` points to the installed app under
`~/Library/Input Methods/hisle.app`, and `clientBundleIdentifier=` plus
`profile=` match the app-specific backend under test. All builds include this
identity on controller initialization and activation lifecycle logs.

Run `nix develop --command -- make version-check` whenever version declarations
are changed.

## Closing A Bug

Before treating a tracked bug as fixed:

- update the bug's Markdown notes with the final behavior and verification
  evidence
- update `bugfix/<bug-name>/status`
- run the verification route from `AGENTS.md` for the changed ownership area
