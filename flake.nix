{
  description = "Hisle, a small Korean input method focused on personal preferences";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    inputs:
    let
      pkgs = inputs.nixpkgs.legacyPackages.aarch64-darwin;
    in
    {
      homeManagerModule = ./home-manager.nix;

      overlay = final: prev: {
        hisle = final.callPackage ./package.nix { };
      };

      packages.aarch64-darwin.default = pkgs.callPackage ./package.nix { };
      packages.aarch64-darwin.hisle = pkgs.callPackage ./package.nix { };

      devShells.aarch64-darwin.default = pkgs.mkShell {
        packages = [
          pkgs.nushell
          pkgs.swiftlint
          pkgs.undmg
        ];
        shellHook = ''
          export HISLE_DEV_SHELL=default
          export PATH="$PATH:/usr/bin:/bin"
          export NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING=1
          unset CC CXX LD SDKROOT NIX_CC NIX_CFLAGS_COMPILE NIX_CFLAGS_LINK NIX_LDFLAGS
          if [ -d /Applications/Xcode.app/Contents/Developer ]; then
            export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
          fi
        '';
      };

      devShells.aarch64-darwin.core = pkgs.mkShell {
        packages = [
          pkgs.nushell
          pkgs.swift
          pkgs.swiftpm
        ];
        shellHook = ''
          export HISLE_DEV_SHELL=core
          export PATH="$PATH:/usr/bin:/bin"
          export NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING=1
        '';
      };

      devShells.aarch64-darwin.browser = pkgs.mkShell {
        packages = [
          pkgs.geckodriver
          pkgs.nodejs
          pkgs.nushell
          pkgs.swiftlint
          pkgs.undmg
        ];
        shellHook = ''
          export HISLE_DEV_SHELL=browser
          export PATH="$PATH:/usr/bin:/bin"
          export NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING=1
          unset CC CXX LD SDKROOT NIX_CC NIX_CFLAGS_COMPILE NIX_CFLAGS_LINK NIX_LDFLAGS
          if [ -d /Applications/Xcode.app/Contents/Developer ]; then
            export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
          fi
        '';
      };

      devShells.aarch64-darwin.icon = pkgs.mkShell {
        packages = [
          pkgs.imagemagick
          pkgs.nushell
          pkgs.resvg
        ];
        shellHook = ''
          export HISLE_DEV_SHELL=icon
          export PATH="$PATH:/usr/bin:/bin"
          export NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING=1
        '';
      };
    };
}
