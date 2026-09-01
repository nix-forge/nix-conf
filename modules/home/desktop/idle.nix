{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  cfg = config.desktop.idle;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  nixosOwnsHypridle = osConfig != null && (osConfig.services.hypridle.enable or false);
  wipeCommand = lib.optionalString (
    config.desktop.clipboard.enable && config.desktop.clipboard.wipeOnLock
  ) "${lib.getExe pkgs.cliphist} wipe";
  hyprBind = key: command: {
    _args = [
      key
      (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON command})")
    ];
  };
in
{
  options.desktop.idle = {
    enable = lib.mkEnableOption "Hypridle lock, DPMS, and suspend policy";

    lockAfterSeconds = lib.mkOption {
      type = lib.types.ints.between 30 3600;
      default = 300;
      description = "Idle time before requesting the logind session lock.";
    };

    displayOffAfterSeconds = lib.mkOption {
      type = lib.types.ints.between 45 7200;
      default = 330;
      description = "Idle time before DPMS turns off the outputs.";
    };

    suspendAfterSeconds = lib.mkOption {
      type = lib.types.ints.between 60 14400;
      default = 900;
      description = "Idle time before system suspend.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isLinux;
        message = "desktop.idle is supported on Linux only.";
      }
      {
        assertion = cfg.lockAfterSeconds < cfg.displayOffAfterSeconds;
        message = "desktop.idle must lock before it turns off the display.";
      }
      {
        assertion = cfg.displayOffAfterSeconds < cfg.suspendAfterSeconds;
        message = "desktop.idle must turn off displays before suspend.";
      }
    ];

    home.packages = [ pkgs.hypridle ];

    xdg.configFile."hypr/hypridle.conf".source = pkgs.replaceVarsWith {
      name = "hypridle-config";
      src = ./config/hypridle.conf.in;
      replacements = {
        lockAfterSeconds = toString cfg.lockAfterSeconds;
        displayOffAfterSeconds = toString cfg.displayOffAfterSeconds;
        suspendAfterSeconds = toString cfg.suspendAfterSeconds;
        onLockCommand = if wipeCommand == "" then "true" else wipeCommand;
      };
    };

    # NixOS enables the packaged unit automatically with Hyprlock. A Home
    # Manager-only profile still needs a unit, but defining one on NixOS would
    # shadow the packaged service and can result in two idle daemons.
    systemd.user.services.hypridle = lib.mkIf (!nixosOwnsHypridle) {
      Unit = {
        Description = "Hyprland idle and lock policy";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${lib.getExe pkgs.hypridle}";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    wayland.windowManager.hyprland.settings.bind =
      lib.mkIf config.wayland.windowManager.hyprland.enable
        (lib.mkAfter [ (hyprBind "SUPER + L" "loginctl lock-session") ]);
  };
}
