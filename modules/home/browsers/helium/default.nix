{
  config,
  inputs,
  lib,
  myLib,
  pkgs,
  system,
  ...
}:
let
  writeBashTemplate = myLib.writers.writeBashTemplate { inherit pkgs; };
  cfg = config.programs.helium;
  inherit (config.programs.browserSuite.chromium) extensionUpdateUrl heliumExtensions;
  extensionIds = builtins.attrValues heliumExtensions;
  # Imports are resolved before pkgs is available through the module system.
  isLinux = lib.hasSuffix "-linux" system;
  isDarwin = lib.hasSuffix "-darwin" system;

  flagArgs = lib.concatMapStringsSep " \\\n      " (
    flag: "--add-flags ${lib.escapeShellArg flag}"
  ) cfg.flags;

  darwinCrxToZip = pkgs.writers.writePython3Bin "helium-crx-to-zip" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ./scripts/crx_to_zip.py;

  # Helium stores its UI preferences in the Chromium profile. Seed these once
  # before the browser starts, so later changes made in Helium's Settings UI
  # remain user-controlled.
  darwinHeliumPreferenceDefaults = pkgs.writers.writePython3Bin "helium-preference-defaults" {
    # Match the project formatter: long lines and leading binary operators.
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ./scripts/preference_defaults.py;

  darwinHeliumPreferenceHook = writeBashTemplate {
    name = "helium-preference-hook";
    src = ./scripts/apply-preference-defaults.sh;
    replacements = {
      bash = lib.getExe pkgs.bash;
      defaults = lib.getExe darwinHeliumPreferenceDefaults;
      defaultsFile = pkgs.writeText "helium-preference-defaults.json" (
        builtins.toJSON {
          values = cfg.preferenceDefaults;
          remove = cfg.preferenceDefaultsRemovals;
        }
      );
      preferencesPath = lib.escapeShellArg "${cfg.profileDirectory}/Preferences";
    };
  };

  # macOS treats unmanaged Chromium policy plist files as "Recommended".
  # Recommended policy cannot force-install extensions, so refresh and load the
  # registry at each Helium start instead. A failed refresh deliberately leaves
  # the previous unpacked extension in place for offline starts. Network timeouts
  # ensure a stalled Web Store request cannot leave Helium waiting indefinitely.
  darwinExtensionUpdateHook = writeBashTemplate {
    name = "helium-extension-update-hook";
    src = ./scripts/extension-update-hook.sh;
    replacements = {
      bash = lib.getExe pkgs.bash;
      extensionIdsFile = pkgs.writeText "helium-extension-ids" (lib.concatStringsSep "\n" extensionIds);
      extensionRoot = lib.escapeShellArg "${dirOf cfg.profileDirectory}/nix-managed-extensions";
      extensionUpdateUrl = lib.escapeShellArg extensionUpdateUrl;
      mkdir = lib.getExe' pkgs.coreutils "mkdir";
      rmdir = lib.getExe' pkgs.coreutils "rmdir";
      mktemp = lib.getExe' pkgs.coreutils "mktemp";
      rm = lib.getExe' pkgs.coreutils "rm";
      mv = lib.getExe' pkgs.coreutils "mv";
      curl = lib.getExe pkgs.curl;
      crxToZip = lib.getExe darwinCrxToZip;
      unzip = lib.getExe pkgs.unzip;
    };
  };

  darwinPackageWithFlags = cfg.package.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
    postInstall =
      (old.postInstall or "")
      + ((import ../../../../lib/templates/text.nix) ./scripts/wrap-darwin-launcher.sh {
        inherit flagArgs;
        lib_escapeShellArg_source_darwinHeliumPreferenceHook_source_ = lib.escapeShellArg "source ${darwinHeliumPreferenceHook}; source ${darwinExtensionUpdateHook}";
      });
  });
in
{
  imports = [
    ../shared
    ./flags.nix
  ]
  ++ lib.optionals isLinux [ inputs.helium-browser.homeModules.default ];
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

    profileDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Library/Application Support/net.imput.helium/Default";
      description = "Helium profile receiving initial preferences. Set this consistently with custom profile or user-data-directory flags.";
    };
    preferenceDefaultsRemovals = lib.mkOption {
      type = lib.types.listOf (lib.types.listOf lib.types.str);
      default = lib.optional (heliumExtensions ? bitwarden) [
        "extensions"
        "commands"
        "mac:Command+Shift+L"
      ];
      description = "Preference key paths removed when initial defaults change. Other application settings remain untouched.";
    };
    preferenceDefaults = lib.mkOption {
      type = lib.types.attrsOf (pkgs.formats.json { }).type;
      default = {
        helium = {
          browser = {
            layout = 2;
            rounded_frame = true;
            zen_mode = true;
            custom_accelerators."34090" = {
              added = [ "Alt+Meta+KeyS" ];
              removed = [ "Meta+KeyS" ];
            };
          };
          settings = {
            a11y.copy_page_url_shortcut = true;
            behavior.vertical_collapse_shortcut = true;
          };
        };
        ntp = {
          personal_shortcuts_visible = false;
          enterprise_shortcuts_visible = false;
        };
      }
      // lib.optionalAttrs (heliumExtensions ? bitwarden) {
        extensions.commands."mac:Command+Alt+Shift+L" = {
          command_name = "autofill_login";
          extension = heliumExtensions.bitwarden;
          global = false;
        };
      };
      description = "Initial profile preference leaves. Applied once per changed declaration; later UI changes persist between launches. Undeclared settings are preserved.";
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
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = lib.all (path: path != [ ]) cfg.preferenceDefaultsRemovals;
          message = "programs.helium.preferenceDefaultsRemovals requires nonempty key paths.";
        }
        {
          assertion = lib.hasPrefix "/" cfg.profileDirectory;
          message = "programs.helium.profileDirectory must be absolute.";
        }
        {
          assertion = !(cfg.preferenceDefaults ? helium) || builtins.isAttrs cfg.preferenceDefaults.helium;
          message = "programs.helium.preferenceDefaults.helium must be an attribute set; the profile stores its revision there.";
        }
      ];
      home.packages = [ darwinPackageWithFlags ];
    })
  ];
}
// lib.optionalAttrs isLinux {
  config = {
    programs.helium.enable = true;
  };
}
