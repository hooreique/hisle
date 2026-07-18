# Getting Started

## Requirements

- Binary install: macOS.
- Source install: Apple Silicon macOS, Xcode at `/Applications/Xcode.app`, and
  Nix with flakes enabled.

## Install From The Release DMG

Fastest: download the `.dmg` from
<https://github.com/hooreique/hisle/releases>, open it, and read the
`Install.txt` inside.

Short version:

1. Copy `hisle.app` to `~/Library/Input Methods/`.
2. Open System Settings > Keyboard > Input Sources.
3. Add `hisle`, then select it from the input menu.

If `hisle` does not appear in Input Sources, log out and back in.

## Install With Home Manager

In an existing Home Manager flake, add the `hisle` input, apply the overlay to
the `pkgs` passed to Home Manager, import the module, and enable the program:

```nix
{
  inputs.hisle.url = "github:hooreique/hisle";

  outputs =
    {
      hisle,
      home-manager,
      nixpkgs,
      ...
    }:
    {
      homeConfigurations."USER" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "aarch64-darwin";
          overlays = [ hisle.overlay ];
        };

        modules = [
          hisle.homeManagerModule
          {
            programs.hisle.enable = true;
          }
        ];
      };
    };
}
```

This copies the packaged app bundle to
`~/Library/Input Methods/hisle.app`. Then add and select `hisle` in System
Settings > Keyboard > Input Sources.

When updating or removing an existing copied app, macOS may require App
Management permission. If activation fails with a permission error, run Home
Manager from a graphical session, grant the permission in System Settings >
Privacy & Security > App Management, then try again.

Disabling `programs.hisle.enable` removes the copied
`~/Library/Input Methods/hisle.app` bundle on the next Home Manager switch.

## Build And Install From Source

Use the Make target instead of launching the input method from Xcode:

```sh
nix develop --command -- make install-debug
```

Then add and select `hisle` in System Settings > Keyboard > Input Sources.

## First Run

`hisle` starts in Roman mode. Tap left Shift by itself for Roman mode, and tap
right Shift by itself for Hangul mode.

Hangul mode uses a personal Cole Sebeol-based layout with `sane-punctuation`;
it is not meant to be a general Korean input method. Shortcut behavior and
mode-switching policy are described in `docs/input-modes.md`.

## App-Specific Host Profiles

`hisle` uses the `default` host profile unless an app is explicitly listed in
`busy-apps.txt`. The `default` profile is the simpler synchronous IMK behavior;
the `busy` profile enables the owned-range and deferred-boundary handling used
for browser and rich-editor compatibility. There is no built-in app list.

The configuration file is:

- `$XDG_CONFIG_HOME/hisle/busy-apps.txt` when `XDG_CONFIG_HOME` is nonempty.
- `$HOME/.config/hisle/busy-apps.txt` otherwise.

The file may be a symbolic link when its target is a regular file. `hisle init`
rejects directories, other non-regular targets, and broken links.

The app does not create the file automatically at startup. To create an empty
file and any missing parent directories with the same XDG/HOME path rule, run:

```sh
"$HOME/Library/Input Methods/hisle.app/Contents/Helpers/hisle" init
```

The command prints the resolved path. It is safe to run again and leaves an
existing file unchanged. Write one case-sensitive macOS bundle identifier per
UTF-8 line. Leading and trailing whitespace, empty lines, and lines whose
trimmed form begins with `#` are ignored. For example:

```text
# Apps that need the busy IMK profile
com.google.Chrome
```

If the file is missing or contains no identifiers, every app uses `default`.
Unreadable or invalid UTF-8 contents also fail safely to an empty list; the
unified log records the read cause.

Use the installed companion CLI to discover the exact identifier. It prints
the current frontmost app immediately, then prints a new unadorned identifier
whenever the frontmost identifier changes:

```sh
"$HOME/Library/Input Methods/hisle.app/Contents/Helpers/hisle" frontmost
```

An app without a bundle identifier is reported on stderr and monitoring
continues. Stop the command with Control-C.

The file is read once when the `hisle` app process starts, and each text-client
controller keeps the profile selected when that controller was created. After
editing the file, restart the process before testing the change:

```sh
pkill -f 'hisle\.app'
```

If the `hisle` input source is active, macOS may immediately launch a new
process. This is expected; a new PID means the new snapshot is in use.

## Update Or Remove

To update a source install, rerun the install command above.

To try a reinstalled build immediately, check the current input method process
after reinstalling:

```sh
pgrep -fl 'hisle\.app'
```

Then stop it:

```sh
pkill -f 'hisle\.app'
```

Check it again:

```sh
pgrep -fl 'hisle\.app'
```

If the `hisle` input source is active, macOS may start a new `hisle` process
right away. In that case, seeing a different PID means the newly installed
bundle is running.

> [!TIP]
> If the steps above do not seem to work, log out of macOS and log back in.

To inspect `hisle` activity at any time, stream its unified log:

```sh
/usr/bin/log stream --style compact --level info --predicate 'subsystem == "hooreique.inputmethod.hisle"'
```

When you switch to the `hisle` input source, the stream prints a
`controller runtime` notice with the build profile, app version, core version,
and build number.

To remove from a source checkout:

```sh
nix develop --command -- make uninstall
```

Manual removal is just removing the installed bundle:

```sh
rm -rf "$HOME/Library/Input Methods/hisle.app"
```
