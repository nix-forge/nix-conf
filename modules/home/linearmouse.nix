{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  cfg = config.programs.linearmouse;
  jsonFormat = pkgs.formats.json { };
  appPath = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/LinearMouse.app";
  legacyConfigFile = "${config.home.homeDirectory}/Library/Application Support/linearmouse/linearmouse.json";
  generatedConfig = jsonFormat.generate "linearmouse.json" cfg.settings;
  stagedConfigDirectory = "${config.xdg.stateHome}/home-manager/linearmouse";
  stagedConfigFile = "${stagedConfigDirectory}/linearmouse.json";
in
{
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
      installLinearMouseConfig = lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "linkGeneration" ] ''
        if [[ ! -f ${lib.escapeShellArg stagedConfigFile} ]] \
          || ! /usr/bin/cmp -s \
            ${lib.escapeShellArg generatedConfig} \
            ${lib.escapeShellArg stagedConfigFile}; then
          run /bin/mkdir -p ${lib.escapeShellArg stagedConfigDirectory}
          run /usr/bin/install -m 0600 \
            ${lib.escapeShellArg generatedConfig} \
            ${lib.escapeShellArg "${stagedConfigFile}.tmp"}
          run /bin/mv -f \
            ${lib.escapeShellArg "${stagedConfigFile}.tmp"} \
            ${lib.escapeShellArg stagedConfigFile}
        fi
      '';

      warnAboutLegacyLinearMouseConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ -e ${lib.escapeShellArg legacyConfigFile} ]; then
          echo "warning: ${legacyConfigFile} takes precedence over the Home Manager-managed LinearMouse configuration" >&2
        fi
      '';

      configureLinearMousePreferences =
        lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ]
          (
            ''
              run /usr/bin/defaults write com.lujjjh.LinearMouse menuBarVisibilityMode \
                -string ${lib.escapeShellArg (builtins.toJSON cfg.menuBarVisibility)}
              run /usr/bin/defaults write com.lujjjh.LinearMouse menuBarVisibilityModeMigrationCompleted -bool true
              run /usr/bin/defaults write com.lujjjh.LinearMouse showInMenuBar \
                -bool ${lib.boolToString (cfg.menuBarVisibility != "never")}
              run /usr/bin/defaults write com.lujjjh.LinearMouse menuBarBatteryDisplayMode \
                -string ${lib.escapeShellArg (builtins.toJSON cfg.menuBarBatteryDisplay)}
              run /usr/bin/defaults write com.lujjjh.LinearMouse showInDock \
                -bool ${lib.boolToString cfg.showInDock}
            ''
            + lib.optionalString cfg.disableAutomaticUpdates ''
              run /usr/bin/defaults write com.lujjjh.LinearMouse SUEnableAutomaticChecks -bool false
              run /usr/bin/defaults write com.lujjjh.LinearMouse SUAutomaticallyUpdate -bool false
            ''
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
          "/bin/wait4path ${lib.escapeShellArg appPath} && exec /usr/bin/open -gj -a ${lib.escapeShellArg appPath}"
        ];
        RunAtLoad = true;
        KeepAlive = false;
        ProcessType = "Interactive";
      };
    };
  };
}
