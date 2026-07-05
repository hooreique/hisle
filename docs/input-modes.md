# Hisle Input Modes

This document specifies the input-mode behavior of the `hisle` input method. It
is intentionally separate from the Cole Sebeol key layout specification. Cole
Sebeol defines the key layout and composition policy used in Hangul mode, while
`hisle` defines the selection policy between Hangul mode and Roman mode.

## Responsibility Boundary

- `hisle` is a macOS input method. It owns input-mode state, modifier-key mode
  selection, InputMethodKit integration, marked text handling, composition
  flushes, and shortcut forwarding.
- `hisle` Hangul mode uses the Cole Sebeol key layout and Hangul automaton.
- `hisle` Roman mode sends Roman letters to the host app through Colemak.
- Cole Sebeol is not responsible for `hisle` mode selection policy. In
  particular, left/right Shift mode selection is `hisle` input-method behavior,
  not part of the Cole Sebeol key layout.

## Modes

`hisle` has two basic input modes.

- Hangul mode: interprets printable Hangul input through Cole Sebeol.
- Roman mode: interprets printable Roman input through Colemak.

Mode selection is absolute selection, not a toggle.

- When the input method starts fresh or no explicit mode has been selected yet,
  it starts in Roman mode.
- When focus moves to a different host app or a newly activated IMK text
  client/session, `hisle` does not preserve a previous Hangul selection for
  that new context; it enters Roman mode.
- When the user switches away to another input method and later selects the
  `hisle` visible input mode again, `hisle` enters Roman mode even if the
  previous `hisle` mode was Hangul mode.
- A left Shift single tap selects Roman mode.
- A right Shift single tap selects Hangul mode.
- Selecting the already active mode does nothing.

Input mode is active editing-context state, not a durable global preference.
Composition buffers and marked text stay client/session-local. The selected mode
may be shared while a client/session remains active, but Hangul mode must not be
relied on to persist across host app switches, newly activated text clients, or
input-source round trips.

## Shift Single Tap

A Shift single tap is a gesture where exactly one Shift key is pressed and then
released. The input method must distinguish left Shift from right Shift.

- If left Shift down is followed by left Shift up without any other meaningful
  input, select Roman mode.
- If right Shift down is followed by right Shift up without any other meaningful
  input, select Hangul mode.
- If a non-Shift key event occurs while Shift is held, cancel the pending mode
  selection.
- If both Shift keys participate in the same gesture, cancel the pending mode
  selection.
- If another modifier key participates in the same gesture, cancel the pending
  mode selection.

Meaningful input includes non-Shift key events and changes to any modifier key
other than the initially pressed Shift. The implementation must treat left/right
Shift as physical key identities, not as characters.

Shift used together with another key remains ordinary Shift input. For example,
when Shift is held with a printable key, the input method must perform that
mode's shifted-key behavior and must not select a mode.

## Composition Boundaries

Mode changes are explicit composition boundaries.

- If Hangul marked text is active when Roman mode is selected, flush the current
  Hangul composition before entering Roman mode.
- When Hangul mode is selected from Roman mode, do not carry Roman-mode
  composition state into Hangul mode.
- When `hisle` is deactivated because the user switched to another input method,
  flush any active Hangul composition.
- Activating a new host app or IMK text client/session is a fresh Roman-mode
  boundary.
- Returning to `hisle` from another input method is a composition boundary
  equivalent to selecting Roman mode.
- Mode selection itself must not emit a Shift character.

## Escape Behavior

Escape acts as a flush and Roman-mode selection boundary, not as cancel.

- If active Hangul marked text exists, Escape commits the current composition.
- Escape selects Roman mode. If Roman mode is already active, it does nothing.
- The Escape event itself is not considered handled and is forwarded to the host
  app. In other words, after performing composition flush and mode selection as
  side effects, the input method returns `false` from `handle`.

## Shortcut Behavior

Modifier shortcuts are not mode-selection gestures. If a Hangul composition is
active, flush it first and then forward the shortcut to the host app according
to the existing shortcut policy.

In Hangul mode, shortcut forwarding follows the `underlying roman layout`
contract defined by Cole Sebeol. Printable text behavior in Roman mode is
Colemak, but that does not mean Cole Sebeol is responsible for `hisle` mode
selection.

## Host Action Keys

Navigation keys and function-row keys are not composition input. If a Hangul
composition is active, flush it first and then forward the key to the host app.
This includes physical Arrow, Home, End, Page Up, Page Down, and F1-F12 keys, as
well as remapping configurations that emit those keys, such as a Karabiner vmod
layer.

## Implementation Notes

The implementation may represent mode state as follows.

```swift
enum HisleInputMode {
    case hangul
    case roman
}
```

The Shift-tap detector must track the pending physical Shift key, whether the
gesture has been canceled, and the current `HisleInputMode`.
