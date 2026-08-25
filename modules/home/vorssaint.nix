{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.vorssaint;

  appPath = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/Vorssaint.app";
in
{
  options.programs.vorssaint = {
    enable = lib.mkEnableOption "Vorssaint, a modular macOS menu-bar toolkit";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.vorssaint;
      defaultText = lib.literalExpression "pkgs.vorssaint";
      description = "Vorssaint package to install.";
    };

    startAtLogin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Launch Vorssaint after a graphical user login. This uses a Home
        Manager-managed launchd agent rather than Vorssaint's own Login Item,
        so leave the app's built-in Launch at Login setting disabled.
      '';
    };

    acknowledgeFanControlLimitation = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Confirm that this configuration intentionally runs without Vorssaint's
        Fan Control feature. Setting this to true suppresses the corresponding
        evaluation warning only; it does not install a privileged helper or
        enable fan control.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (lib.hm.assertions.assertPlatform "programs.vorssaint" pkgs lib.platforms.darwin)
      {
        assertion = !cfg.startAtLogin || config.targets.darwin.copyApps.enable;
        message = "programs.vorssaint.startAtLogin requires targets.darwin.copyApps.enable.";
      }
    ];

    home.packages = [ cfg.package ];

    warnings = lib.optional (!cfg.acknowledgeFanControlLimitation) ''
      programs.vorssaint: Fan Control is unavailable from the Nix package.
      Vorssaint requires its Apple Developer-ID-signed privileged helper, and
      this reproducibly ad-hoc-signed package cannot satisfy that XPC trust
      requirement. The module does not install a substitute root daemon.
    '';

    # LaunchServices and SMAppService require a stable, mutable application
    # location. A copied bundle also avoids running this GUI app from a
    # generation-specific path in the Nix store.
    targets.darwin = {
      copyApps.enable = lib.mkDefault true;
      linkApps.enable = lib.mkDefault false;
    };

    home.activation.waitForCopiedVorssaintApp = lib.mkIf cfg.startAtLogin (
      lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "copyApps" ] ''
        run /bin/wait4path ${lib.escapeShellArg appPath}
      ''
    );

    launchd.agents.vorssaint = lib.mkIf cfg.startAtLogin {
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
