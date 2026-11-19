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
  checkedShellText = myLib.writers.checkedShellText { inherit pkgs; };
  writeBashTemplate = myLib.writers.writeBashTemplate { inherit pkgs; };
  cfg = config.programs.helium;
  inherit (config.programs.browserSuite.chromium) extensionUpdateUrl heliumExtensions;
  extensionIds = builtins.attrValues heliumExtensions;
  # Imports are resolved before pkgs is available through the module system.
  isLinux = lib.hasSuffix "-linux" system;
  isDarwin = lib.hasSuffix "-darwin" system;

  darwinCrxToZip = (import ../../../../flake/runtime-packages.nix { inherit pkgs; }).crxToZip;

  # Helium stores its UI preferences in the Chromium profile. Seed these once
  # before the browser starts, so later changes made in Helium's Settings UI
  # remain user-controlled.
  darwinHeliumPreferenceDefaults =
    (import ../../../../flake/runtime-packages.nix { inherit pkgs; }).heliumPreferenceDefaults;

  darwinHeliumPreferenceHook = writeBashTemplate {
    name = "helium-preference-hook";
    text = ''
      #!@bash@
      # shellcheck shell=bash
      @defaults@ @defaultsFile@ @preferencesPath@ || printf '%s\n' 'Could not apply Helium preference defaults.' >&2
    '';
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
    text = ''
      #!@bash@
      # shellcheck shell=bash
      extension_flag="$(@updater@ list @extensionRoot@ @extensionIdsFile@ @extensionUpdateUrl@ @curl@ @unzip@)"
      @updater@ update @extensionRoot@ @extensionIdsFile@ @extensionUpdateUrl@ @curl@ @unzip@ >/dev/null 2>&1 &
      [ -z "$extension_flag" ] || set -- "$extension_flag" "$@"
    '';
    replacements = {
      bash = lib.getExe pkgs.bash;
      extensionIdsFile = pkgs.writeText "helium-extension-ids" (lib.concatStringsSep "\n" extensionIds);
      extensionRoot = lib.escapeShellArg "${dirOf cfg.profileDirectory}/nix-managed-extensions";
      extensionUpdateUrl = lib.escapeShellArg extensionUpdateUrl;
      updater = lib.getExe' darwinCrxToZip "helium-extension-update";
      curl = lib.getExe pkgs.curl;
      unzip = lib.getExe pkgs.unzip;
    };
  };

  # Finder and Dock launches must select Helium Launcher.app for flags/hooks.
  # Direct launches of the unchanged vendor Helium.app retain vendor behavior.
  # Invoke the selected upstream CLI wrapper, retaining its updater-disable
  # argument and any future upstream launcher setup. Never rewrite signed code.
  darwinLauncher = writeBashTemplate {
    name = "helium";
    text = ''
      #!@bash@
      # shellcheck shell=bash
      # shellcheck source=/dev/null
      source @preferenceHook@
      # shellcheck source=/dev/null
      source @extensionHook@
      exec @browser@ @flags@ "$@"
    '';
    dir = "bin";
    replacements = {
      bash = lib.getExe pkgs.bash;
      preferenceHook = darwinHeliumPreferenceHook;
      extensionHook = darwinExtensionUpdateHook;
      browser = lib.getExe cfg.package;
      flags = lib.escapeShellArgs cfg.flags;
    };
  };
  darwinLauncherApp = pkgs.stdenv.mkDerivation {
    pname = "helium-launcher";
    version = cfg.package.version;
    src = ./scripts/launcher.swift;
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.swift
      pkgs.rcodesign
    ];
    buildPhase = checkedShellText {
      name = "build-helium-launcher";
      text = ''
        # Nix supplies the immutable Swift source and builder hooks.
        # shellcheck disable=SC2154
        runHook preBuild
        swiftc -swift-version 5 -O "$src" -o helium-launcher
        runHook postBuild
      '';
    };
    installPhase = checkedShellText {
      name = "install-helium-launcher";
      text =
        myLib.templates.renderText
          {
            name = "install-launcher.sh";
            text = ''
              # shellcheck shell=bash
              # shellcheck disable=SC2154
              runHook preInstall
              app="$out/Applications/Helium Launcher.app"
              mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
              cp helium-launcher "$app/Contents/MacOS/helium-launcher"
              cp @launcherPlist@ "$app/Contents/Info.plist"
              printf '%s\n' @launcherExecutable@ >"$app/Contents/Resources/launcher.txt"
              if [ -f "@vendor@/Applications/Helium.app/Contents/Resources/app.icns" ]; then
                cp "@vendor@/Applications/Helium.app/Contents/Resources/app.icns" "$app/Contents/Resources/app.icns"
              fi
              runHook postInstall
            '';
          }
          {
            launcherPlist = ./scripts/launcher.plist;
            launcherExecutable = lib.escapeShellArg (lib.getExe darwinLauncher);
            vendor = cfg.package;
          };
    };
    postFixup = checkedShellText {
      name = "seal-helium-launcher";
      text = ''
        # Seal only our helper after Mach-O fixups, preserving the vendor signature.
        # shellcheck disable=SC2154
        rcodesign sign "$out/Applications/Helium Launcher.app"
      '';
    };
  };
  darwinPackageWithFlags =
    (pkgs.linkFarm "helium-with-launcher-${cfg.package.version}" {
      "Applications/Helium.app" = "${cfg.package}/Applications/Helium.app";
      "Applications/Helium Launcher.app" = "${darwinLauncherApp}/Applications/Helium Launcher.app";
      "bin/helium" = lib.getExe darwinLauncher;
    }).overrideAttrs
      (_: {
        inherit (cfg.package) version;
        passthru = {
          vendor = cfg.package;
          launcher = darwinLauncherApp;
        };
        meta = cfg.package.meta // {
          mainDarwinApp = "Helium Launcher.app";
        };
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
      default =
        (import ../../../../overlays/temporary { inherit inputs pkgs; }).apply "helium-darwin-app-metadata"
          inputs.helium-browser-darwin.packages.${system}.default;
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
