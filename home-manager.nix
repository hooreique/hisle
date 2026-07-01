{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.hisle;
  appBundle = "${cfg.package}/Library/Input Methods/hisle.app";
  targetDirectory = "Library/Input Methods";
  installedAppName = "hisle.app";
in
{
  # Workaround for warning: Using 'builtins.derivation' to create a derivation named 'options.json' that references the store path...
  _file = "github:hooreique/hisle";

  options.programs.hisle = {
    enable = lib.mkEnableOption "hisle Korean input method";

    package = lib.mkPackageOption pkgs "hisle" { };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        (lib.hm.assertions.assertPlatform "programs.hisle" pkgs lib.platforms.darwin)
      ];

      home.activation.installHisleInputMethod =
        lib.hm.dag.entryAfter
          [
            "installPackages"
            "linkGeneration"
          ]
          ''
            sourceApp=${lib.escapeShellArg appBundle}
            targetDir="$HOME/${targetDirectory}"
            targetApp="$targetDir/${installedAppName}"

            if [[ ! -d "$sourceApp" ]]; then
              echo "error: hisle app bundle not found at $sourceApp" >&2
              exit 1
            fi

            run mkdir -p "$targetDir"

            if [[ -L "$targetApp" || ( -e "$targetApp" && ! -d "$targetApp" ) ]]; then
              run rm -rf "$targetApp"
            fi

            run mkdir -p "$targetApp"

            rsyncFlags=(
              --archive
              --checksum
              --copy-unsafe-links
              --delete
              --chmod=+w
              --no-group
              --no-owner
              --no-times
            )

            run ${lib.getExe pkgs.rsync} "''${rsyncFlags[@]}" "$sourceApp/" "$targetApp/"
          '';
    })

    (lib.mkIf (!cfg.enable && pkgs.stdenv.hostPlatform.isDarwin) {
      home.activation.removeHisleInputMethod =
        lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
          ''
            targetApp="$HOME/${targetDirectory}/${installedAppName}"

            if [[ -e "$targetApp" || -L "$targetApp" ]]; then
              run rm -rf "$targetApp"
            fi
          '';
    })
  ];
}
