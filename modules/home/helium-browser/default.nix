{
  config,
  inputs,
  lib,
  pkgs,
  system,
  ...
}:
let
  cfg = config.programs.helium;
  isLinux = builtins.elem system [
    "x86_64-linux"
    "aarch64-linux"
  ];
  isDarwin = builtins.elem system [
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  flagArgs = lib.concatMapStringsSep " \\\n      " (
    flag: "--add-flags ${lib.escapeShellArg flag}"
  ) cfg.flags;

  darwinPackageWithFlags =
    if cfg.flags == [ ] then
      cfg.package
    else
      cfg.package.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
        postInstall = (old.postInstall or "") + ''
          heliumApp="$out/Applications/Helium.app"
          heliumExe="$heliumApp/Contents/MacOS/Helium"

          if [ -x "$heliumExe" ] && [ ! -e "$heliumExe-unwrapped" ]; then
            mv "$heliumExe" "$heliumExe-unwrapped"
            makeWrapper "$heliumExe-unwrapped" "$heliumExe" \
              ${flagArgs}

            rm -f "$out/bin/helium"
            makeWrapper "$heliumExe-unwrapped" "$out/bin/helium" \
              ${flagArgs}
          fi
        '';
      });
in
{
  imports = [ ./flags.nix ] ++ lib.optionals isLinux [ inputs.helium-browser.homeModules.default ];
}
// lib.optionalAttrs isDarwin {
  options.programs.helium = {
    enable = lib.mkEnableOption "Helium Browser";

    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.helium-browser-darwin.packages.${system}.default;
      defaultText = "inputs.helium-browser-darwin.packages.\${system}.default";
      description = "The Helium package to use.";
    };

    flags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "--no-first-run"
        "--no-default-browser-check"
      ];
      description = "Additional command-line flags passed to Helium.";
    };
  };

  config = lib.mkMerge [
    { programs.helium.enable = true; }
    (lib.mkIf cfg.enable { home.packages = [ darwinPackageWithFlags ]; })
  ];
}
// lib.optionalAttrs isLinux {
  config = {
    programs.helium.enable = true;
  };
}
