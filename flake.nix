{
  description = "hisle development shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = inputs: let
    system = "aarch64-darwin";
    pkgs = inputs.nixpkgs.legacyPackages.${system};
    commonShellHook = ''
      export PATH="$PATH:/usr/bin:/bin"
      export NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING=1
    '';
    commonPackages = [
      pkgs.nushell
      pkgs.swift
      pkgs.swiftpm
      pkgs.undmg
    ];
  in {
    devShells.${system} = {
      default = pkgs.mkShell {
        packages = commonPackages;
        shellHook = commonShellHook;
      };

      xcode-work = pkgs.mkShell {
        packages = commonPackages;
        shellHook = commonShellHook + ''
          if [ -d /Applications/Xcode.app/Contents/Developer ]; then
            export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
          fi
        '';
      };

      icon-work = pkgs.mkShell {
        packages = commonPackages ++ [
          pkgs.imagemagick
          pkgs.resvg
        ];
        shellHook = commonShellHook;
      };

      browser-work = pkgs.mkShell {
        packages = commonPackages ++ [
          pkgs.nodejs
        ];
        shellHook = commonShellHook;
      };
    };
  };
}
