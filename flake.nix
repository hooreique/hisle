{
  description = "Hisle, a small Korean input method focused on personal preferences";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    inputs:
    let
      pkgs = inputs.nixpkgs.legacyPackages.aarch64-darwin;
      shellHook = ''
        export PATH="$PATH:/usr/bin:/bin"
        export NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING=1
      '';
      packages = [
        pkgs.nushell
        pkgs.swift
        pkgs.swiftpm
        pkgs.undmg
      ];
    in
    {
      homeManagerModule = ./home-manager.nix;

      overlay = final: prev: {
        hisle = final.callPackage ./package.nix { };
      };

      packages.aarch64-darwin.default = pkgs.callPackage ./package.nix { };
      packages.aarch64-darwin.hisle = pkgs.callPackage ./package.nix { };

      devShells.aarch64-darwin.default = pkgs.mkShell {
        inherit packages shellHook;
      };

      devShells.aarch64-darwin.xcode-work = pkgs.mkShell {
        inherit packages;
        shellHook = shellHook + ''
          if [ -d /Applications/Xcode.app/Contents/Developer ]; then
            export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
          fi
        '';
      };

      devShells.aarch64-darwin.icon-work = pkgs.mkShell {
        inherit shellHook;
        packages = packages ++ [
          pkgs.imagemagick
          pkgs.resvg
        ];
      };

      devShells.aarch64-darwin.browser-work = pkgs.mkShell {
        inherit shellHook;
        packages = packages ++ [
          pkgs.nodejs
        ];
      };
    };
}
