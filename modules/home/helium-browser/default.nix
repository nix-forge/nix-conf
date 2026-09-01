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
  inherit (config.programs.browserPolicy.chromium) extensionUpdateUrl heliumExtensions;
  extensionIds = builtins.attrValues heliumExtensions;
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

  darwinCrxToZip = builtins.path {
    path = ./scripts/crx-to-zip.py;
    name = "helium-crx-to-zip.py";
  };

  # Helium stores its UI preferences in the Chromium profile. Seed these once
  # before the browser starts, so later changes made in Helium's Settings UI
  # remain user-controlled.
  darwinHeliumPreferenceDefaults = builtins.path {
    path = ./scripts/preference-defaults.py;
    name = "helium-preference-defaults.py";
  };

  darwinHeliumPreferenceHook = pkgs.replaceVarsWith {
    name = "helium-preference-hook";
    src = ./scripts/preference-hook.sh;
    replacements = {
      bash = lib.getExe pkgs.bash;
      python = lib.getExe pkgs.python3;
      defaults = darwinHeliumPreferenceDefaults;
    };
  };

  # macOS treats unmanaged Chromium policy plist files as "Recommended".
  # Recommended policy cannot force-install extensions, so refresh and load the
  # registry at each Helium start instead. A failed refresh deliberately leaves
  # the previous unpacked extension in place for offline starts. Network timeouts
  # ensure a stalled Web Store request cannot leave Helium waiting indefinitely.
  darwinExtensionUpdateHook = pkgs.replaceVarsWith {
    name = "helium-extension-update-hook";
    src = ./scripts/extension-update-hook.sh;
    replacements = {
      bash = lib.getExe pkgs.bash;
      extensionIdsFile = pkgs.writeText "helium-extension-ids" (lib.concatStringsSep "\n" extensionIds);
      extensionUpdateUrl = lib.escapeShellArg extensionUpdateUrl;
      mkdir = lib.getExe' pkgs.coreutils "mkdir";
      rmdir = lib.getExe' pkgs.coreutils "rmdir";
      mktemp = lib.getExe' pkgs.coreutils "mktemp";
      rm = lib.getExe' pkgs.coreutils "rm";
      mv = lib.getExe' pkgs.coreutils "mv";
      curl = lib.getExe pkgs.curl;
      python = lib.getExe pkgs.python3;
      crxToZip = darwinCrxToZip;
      unzip = lib.getExe pkgs.unzip;
    };
  };

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
              ${flagArgs} \
              --run ${lib.escapeShellArg "source ${darwinHeliumPreferenceHook}; source ${darwinExtensionUpdateHook}"}

            rm -f "$out/bin/helium"
            makeWrapper "$heliumExe-unwrapped" "$out/bin/helium" \
              ${flagArgs} \
              --run ${lib.escapeShellArg "source ${darwinHeliumPreferenceHook}; source ${darwinExtensionUpdateHook}"}
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
