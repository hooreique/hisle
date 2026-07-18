# App-Specific IMK Backends

## Definition

The owned-range and deferred-boundary changes that fixed Chrome/Confluence and
Firefox regressions became the only IMK host-integration path. Simpler native
clients therefore could not retain the complete v0.1.8 behavior independently
of the browser/rich-editor workarounds.

Expected behavior:

- load one exact-match busy-app bundle identifier snapshot before IMK startup
- keep v0.1.8 synchronous range, boundary, fallback, and lifecycle behavior as
  the `default` backend
- keep the v0.1.15 owned-range, queue, generation, ticket, and aggregate
  behavior as the `busy` backend
- fix the selected backend for each controller and keep backend state isolated
- provide explicit, idempotent configuration initialization that creates an
  empty file and missing parents without replacing an existing list
- provide a companion CLI monitor for discovering frontmost bundle identifiers

## Implementation

`BusyAppsSnapshot` resolves the XDG/HOME configuration path, trims line framing
and comments while preserving identifier spelling and case for exact matching,
and fails safely to an empty set. `AppDelegate` installs it before
`InputMethodServer` starts. `InputController` identifies the initial
`IMKTextInput` client and routes every host-integration callback to one
`DefaultHostBackend` or `BusyHostBackend` instance.

The default backend is a near-mechanical restoration of the v0.1.8 controller,
composition, key-handling, and marked-range policy. The busy backend owns the
previous current implementation unchanged. The two backend objects share only
common engine/classifier/Shift/mode policy types, not pending or deferred
state. Runtime lifecycle logs include the client identifier and selected
profile.

The bundled helper adds `hisle init` and `hisle frontmost`. `init` reuses the
app's exact XDG/HOME resolver, creates missing parent directories, and uses an
exclusive file create so repeated runs never truncate an existing list. App
startup remains read-only. The original no-argument mode and `--version`
output remain unchanged.

## Verification

Verified on 2026-07-15:

- `make swiftlint`, `make version-check`, the 524-check core specification, and
  a Debug `make build` passed.
- `make busy-apps-configuration-check` passed 11 configuration and explicit
  initialization cases. `make hisle-cli-check` passed temporary XDG/HOME path
  creation, repeated invocation and content preservation, exact path output,
  destination collision stderr/status, and the existing mode, version, and
  help contracts without touching the user configuration path.
- `make marked-range-policy-check` passed both profiles, 20 busy selection
  cases, and default pending continuation.
- `make deferred-boundary-check` passed the default synchronous/scalar cases
  and all busy queue, ordering, lifecycle, ticket, and reentry cases.
- `make frontmost-monitor-check` passed initial output, changes, duplicate
  suppression, missing identifiers, continuation, line framing, and flushing.
- With no configuration file, `make gui-smoke-test` produced the exact Sublime
  Text result and logged `com.sublimetext.4 profile=default` on build 30. The
  original helper contracts returned `roman`, `hisle 0.1.16-debug`, and
  `hisle-core 0.1.1`. After this verification, the distribution version for
  the completed fix was advanced from 0.1.16 to 0.1.17; build 30 was retained.
- With only `com.google.Chrome` in the temporary configuration snapshot,
  `make chrome-ime-repro` passed with zero anomaly counts and logged
  `profile=busy`. Evidence is under
  `build/chrome-ime/20260715-001332-yYxFNU`.
- The live Confluence `annyeong-space-backspace` scenario passed exact expected
  text matching with Chrome logged as `profile=busy`. Evidence is under
  `local/atlassian/runs/20260715-001412-CrRipK`.

Microsoft Teams was installed but was not exercised because an authenticated
manual test session was not established. The temporary Chrome configuration
file was removed after the browser runs, restoring the original missing-file
state.
