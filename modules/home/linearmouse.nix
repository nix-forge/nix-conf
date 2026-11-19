{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  checkedShellText = myLib.writers.checkedShellText { inherit pkgs; };
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  cfg = config.programs.linearmouse;
  schemaSource = import ./linearmouse-assets/schema-source.nix;
  jsonFormat = pkgs.formats.json { };
  appPath = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/LinearMouse.app";
  legacyConfigFile = "${config.home.homeDirectory}/Library/Application Support/linearmouse/linearmouse.json";
  renderedConfig = jsonFormat.generate "linearmouse.json" cfg.settings;
  generatedConfig =
    pkgs.runCommand "checked-linearmouse.json"
      {
        nativeBuildInputs = [
          pkgs.check-jsonschema
          pkgs.jq
        ];
      }
      (
        myLib.templates.renderText
          {
            name = "checked-config.sh";
            text = ''
              # shellcheck shell=bash
              # Build/activation supplies these variables and functions.
              # shellcheck disable=SC2154,SC2329
              # All references must be bundled in the pinned schema, including overrides.
              jq -e -f @referencesFilter@ @lib_escapeShellArg_cfg_settingsSchema@ >/dev/null || {
                echo 'LinearMouse settingsSchema must be self-contained; external references are not supported.' >&2
                exit 1
              }
              check-jsonschema --schemafile @lib_escapeShellArg_cfg_settingsSchema@ @renderedConfig@
              cp @renderedConfig@ "$out"
            '';
          }
          {
            referencesFilter = ./linearmouse-assets/schema-references.jq;
            lib_escapeShellArg_cfg_settingsSchema = lib.escapeShellArg cfg.settingsSchema;
            inherit renderedConfig;
          }
      );
  stagedConfigDirectory = "${config.xdg.stateHome}/home-manager/linearmouse";
  stagedConfigFile = "${stagedConfigDirectory}/linearmouse.json";
in
{
  imports = [ ./macos/application-capabilities.nix ];
  options.programs.linearmouse = {
    enable = lib.mkEnableOption "LinearMouse, a customizable mouse and trackpad utility for macOS";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.linearmouse;
      defaultText = lib.literalExpression "pkgs.linearmouse";
      description = "LinearMouse package to install.";
    };

    settings = lib.mkOption {
      inherit (jsonFormat) type;
      default = { };
      description = ''
        LinearMouse settings written to
        {file}`~/.config/linearmouse/linearmouse.json`.

        An existing
        {file}`~/Library/Application Support/linearmouse/linearmouse.json`
        takes precedence and must be removed or migrated manually.
      '';
    };

    settingsSchema = lib.mkOption {
      type = lib.types.path;
      default =
        if cfg.package ? configurationSchema then
          if (cfg.package.configurationSchemaVersion or null) == lib.getVersion cfg.package then
            cfg.package.configurationSchema
          else
            throw "programs.linearmouse: the selected package schema version does not match"
        else if lib.getVersion cfg.package == schemaSource.version then
          pkgs.fetchurl schemaSource.src
        else
          throw "programs.linearmouse: review the schema for the selected upstream version or set settingsSchema explicitly";
      defaultText = lib.literalExpression "the version-matched upstream configuration schema";
      description = ''
        Pinned, self-contained JSON Schema for the selected LinearMouse version.
        The module pins the matching schema independently of the upstream package.
        Override this explicitly when selecting a different application version.
        Generated settings must validate against this schema before installation.
        External schema references are rejected so validation remains offline.
      '';
    };

    settingsFile = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      internal = true;
      default = generatedConfig;
      description = "Generated LinearMouse configuration after schema validation.";
    };

    startAtLogin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Start the Home Manager-copied LinearMouse application with a GUI-domain
        launchd agent. Leave LinearMouse's built-in Start at login setting off
        when using this option.
      '';
    };

    disableAutomaticUpdates = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Disable Sparkle's scheduled update checks and automatic downloads in
        the LinearMouse preferences domain without modifying the signed app.
        The manual Check for Updates menu item remains available.
      '';
    };

    menuBarVisibility = lib.mkOption {
      type = lib.types.enum [
        "always"
        "whenAttentionNeeded"
        "never"
      ];
      default = "always";
      description = ''
        When LinearMouse's menu bar item is visible. The
        `whenAttentionNeeded` mode shows it when LinearMouse needs attention,
        such as when Accessibility permission is missing.
      '';
    };

    menuBarBatteryDisplay = lib.mkOption {
      type = lib.types.enum [
        "off"
        "below5"
        "below10"
        "below15"
        "below20"
        "always"
      ];
      default = "off";
      description = ''
        When the current pointing device's battery percentage is shown in the
        menu bar item. Keep this off for devices that do not report a battery
        level to macOS.
      '';
    };

    showInDock = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether LinearMouse is shown in the Dock.";
    };
  };

  config = lib.mkIf cfg.enable {
    macos.applicationCapabilities.apps.linearmouse = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      enable = lib.mkDefault cfg.enable;
      bundle = "LinearMouse.app";
      bundleId = "com.lujjjh.LinearMouse";
      teamId = "C5686NKYJ7";
      features = {
        pointerCustomization = {
          enable = lib.mkDefault true;
          service = "accessibility";
          reason = "Customize mouse scrolling and pointer behavior";
          source = "https://github.com/linearmouse/linearmouse/blob/main/ACCESSIBILITY.md";
          instruction = "Test scroll reversal with the intended mouse in a harmless window.";
        };
      };
    };

    assertions = [
      {
        assertion = isDarwin;
        message = "programs.linearmouse is only supported on Darwin.";
      }
      {
        assertion = !cfg.startAtLogin || config.targets.darwin.copyApps.enable;
        message = "programs.linearmouse.startAtLogin requires targets.darwin.copyApps.enable.";
      }
    ];

    home.packages = [ cfg.package ];

    # A real copy in a stable user Applications directory integrates with
    # Spotlight and LaunchServices and avoids launching directly from the
    # immutable, generation-specific Nix store path.
    targets.darwin.copyApps.enable = lib.mkDefault true;

    # LinearMouse resolves the generated file's symlink and watches its parent
    # directory. Keep the final target outside /nix/store so ordinary Nix store
    # activity does not wake its configuration watcher.
    xdg.configFile."linearmouse/linearmouse.json".source =
      config.lib.file.mkOutOfStoreSymlink stagedConfigFile;

    home.activation = {
      installLinearMouseConfig = lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "linkGeneration" ] (
        myLib.templates.renderText
          {
            name = "stage-config.sh";
            text = ''
              # shellcheck shell=bash
              if [[ ! -f @lib_escapeShellArg_stagedConfigFile@ ]] ||
                ! /usr/bin/cmp -s \
                  @lib_escapeShellArg_cfg_settingsFile@ \
                  @lib_escapeShellArg_stagedConfigFile@; then
                run /bin/mkdir -p @lib_escapeShellArg_stagedConfigDirectory@
                run /usr/bin/install -m 0600 \
                  @lib_escapeShellArg_cfg_settingsFile@ \
                  @lib_escapeShellArg_stagedConfigFile_tmp@
                run /bin/mv -f \
                  @lib_escapeShellArg_stagedConfigFile_tmp@ \
                  @lib_escapeShellArg_stagedConfigFile@
              fi
            '';
          }
          {
            lib_escapeShellArg_stagedConfigFile = lib.escapeShellArg stagedConfigFile;
            lib_escapeShellArg_cfg_settingsFile = lib.escapeShellArg cfg.settingsFile;
            lib_escapeShellArg_stagedConfigDirectory = lib.escapeShellArg stagedConfigDirectory;
            lib_escapeShellArg_stagedConfigFile_tmp = lib.escapeShellArg "${stagedConfigFile}.tmp";
          }
      );

      warnAboutLegacyLinearMouseConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] (
        myLib.templates.renderText
          {
            name = "warn-legacy-config.sh";
            text = ''
              # shellcheck shell=bash
              if [ -e @lib_escapeShellArg_legacyConfigFile@ ]; then
                echo "warning: @legacyConfigFile@ takes precedence over the Home Manager-managed LinearMouse configuration" >&2
              fi
            '';
          }
          {
            lib_escapeShellArg_legacyConfigFile = lib.escapeShellArg legacyConfigFile;
            inherit legacyConfigFile;
          }
      );

      configureLinearMousePreferences =
        lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ]
          (
            (myLib.templates.renderText
              {
                name = "configure-preferences.sh";
                text = ''
                  # shellcheck shell=bash
                  # Sourced by Home Manager or the owning build phase.
                  run /usr/bin/defaults write com.lujjjh.LinearMouse menuBarVisibilityMode \
                    -string @lib_escapeShellArg_builtins_toJSON_cfg_menuBarVisibility@
                  run /usr/bin/defaults write com.lujjjh.LinearMouse menuBarVisibilityModeMigrationCompleted -bool true
                  run /usr/bin/defaults write com.lujjjh.LinearMouse showInMenuBar \
                    -bool @lib_boolToString_cfg_menuBarVisibility_never@
                  run /usr/bin/defaults write com.lujjjh.LinearMouse menuBarBatteryDisplayMode \
                    -string @lib_escapeShellArg_builtins_toJSON_cfg_menuBarBatteryDisplay@
                  run /usr/bin/defaults write com.lujjjh.LinearMouse showInDock \
                    -bool @lib_boolToString_cfg_showInDock@
                '';
              }
              {
                lib_escapeShellArg_builtins_toJSON_cfg_menuBarVisibility = lib.escapeShellArg (
                  builtins.toJSON cfg.menuBarVisibility
                );
                lib_boolToString_cfg_menuBarVisibility_never = lib.boolToString (cfg.menuBarVisibility != "never");
                lib_escapeShellArg_builtins_toJSON_cfg_menuBarBatteryDisplay = lib.escapeShellArg (
                  builtins.toJSON cfg.menuBarBatteryDisplay
                );
                lib_boolToString_cfg_showInDock = lib.boolToString cfg.showInDock;
              }
            )
            + lib.optionalString cfg.disableAutomaticUpdates ((''
              # shellcheck shell=bash
              # Variables and functions are supplied by the owning activation or build phase.
              run /usr/bin/defaults write com.lujjjh.LinearMouse SUEnableAutomaticChecks -bool false
              run /usr/bin/defaults write com.lujjjh.LinearMouse SUAutomaticallyUpdate -bool false
            ''))
          );

      waitForCopiedLinearMouseApp = lib.mkIf cfg.startAtLogin (
        lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "copyApps" ] ''
          run /bin/wait4path ${lib.escapeShellArg appPath}
        ''
      );
    };

    launchd.agents.linearmouse = lib.mkIf cfg.startAtLogin {
      enable = true;
      domain = "gui";
      config = {
        ProgramArguments = [
          "/bin/sh"
          "-c"
          (checkedShellText {
            name = "launch-linearmouse";
            shell = "sh";
            text = "/bin/wait4path ${lib.escapeShellArg appPath} && exec /usr/bin/open -gj -a ${lib.escapeShellArg appPath}";
          })
        ];
        RunAtLoad = true;
        KeepAlive = false;
        ProcessType = "Interactive";
      };
    };
  };
}
