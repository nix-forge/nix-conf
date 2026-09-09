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
  onLockCommand = lib.concatStringsSep "; " (
    lib.filter (command: command != "" && command != "true") [
      wipeCommand
      cfg.onLockCommand
    ]
  );
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

    lockedDisplayOffAfterSeconds = lib.mkOption {
      type = lib.types.ints.between 10 300;
      default = 30;
      description = ''
        Input idle time before turning off outputs while Hyprlock is running,
        even when applications inhibit idle. Already-idle sessions retry the
        lock check every five seconds. Input wakes the display for unlocking.
      '';
    };

    suspendAfterSeconds = lib.mkOption {
      type = lib.types.ints.between 60 14400;
      default = 900;
      description = "Idle time before system suspend.";
    };

    onLockCommand = lib.mkOption {
      type = lib.types.str;
      default = "true";
      description = ''
        Extra user-session command run after locking. Use it for state that
        must be cleared at the lock boundary, such as shell-owned clipboard
        history.
      '';
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

    xdg.configFile."hypr/hypridle.conf".text = lib.hm.generators.toHyprconf {
      attrs = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          # Wait for Hyprlock to confirm the lock before logind permits sleep.
          inhibit_sleep = 3;
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
          on_lock_cmd = if onLockCommand == "" then "true" else onLockCommand;
          on_unlock_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
        };
        listener = [
          {
            timeout = cfg.lockAfterSeconds;
            on-timeout = "loginctl lock-session";
          }
          {
            timeout = cfg.displayOffAfterSeconds;
            on-timeout = "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'";
            on-resume = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
          }
          {
            # Only the locked-session rule bypasses application inhibitors.
            # Retry if the short timeout expires before Hyprlock starts.
            timeout = cfg.lockedDisplayOffAfterSeconds;
            ignore_inhibit = true;
            condition_cmd = ''pgrep -u "$(id -u)" -x hyprlock > /dev/null'';
            condition_retry = 5;
            on-timeout = "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'";
            on-resume = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
          }
          {
            timeout = cfg.suspendAfterSeconds;
            on-timeout = "systemctl suspend";
          }
        ];
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
