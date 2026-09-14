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
  sessionLock = pkgs.writeShellApplication {
    name = "desktop-session-lock";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      exec ${pkgs.bash}/bin/bash ${./scripts/session-lock.sh} "$@" \
        ${lib.getExe config.programs.hyprlock.package} \
        --config ${lib.escapeShellArg "${config.xdg.configHome}/hypr/hyprlock.conf"}
    '';
  };
  filterNativeInhibitors = cfg.backgroundAppClasses != [ ];
  inhibitorCheck = pkgs.writeShellApplication {
    name = "desktop-idle-inhibit-check";
    runtimeInputs = [ config.wayland.windowManager.hyprland.package ];
    text = ''
      exec ${lib.getExe pkgs.python3} ${./scripts/idle-inhibit-check.py} "$@"
    '';
  };
  screenCondition = lib.optionalAttrs filterNativeInhibitors {
    condition_cmd = "${lib.getExe inhibitorCheck} screen -- ${lib.escapeShellArgs cfg.backgroundAppClasses}";
    condition_retry = 5;
  };
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

    backgroundAppClasses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Exact Hyprland window classes whose native Wayland idle inhibitors
        may defer suspend but not automatic locking or display sleep.
        Other windows retain their native inhibition. D-Bus screen inhibitors
        are unaffected. Requires Hyprland and its clients IPC interface.
      '';
    };

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
        assertion = !filterNativeInhibitors || config.wayland.windowManager.hyprland.enable;
        message = "desktop.idle.backgroundAppClasses requires Hyprland.";
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

    home.packages = [
      pkgs.hypridle
      sessionLock
    ];

    xdg.configFile."hypr/hypridle.conf".text = lib.hm.generators.toHyprconf {
      attrs = {
        general = {
          lock_cmd = "${lib.getExe sessionLock} lock";
          # Wait for Hyprlock to confirm the lock before logind permits sleep.
          inhibit_sleep = 3;
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
          on_lock_cmd = if onLockCommand == "" then "true" else onLockCommand;
          on_unlock_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
        }
        // lib.optionalAttrs filterNativeInhibitors {
          # Chromium requests a native screen inhibitor even for background
          # work. Check native inhibitors separately for screen and suspend.
          ignore_wayland_inhibit = true;
        };
        listener = [
          (
            {
              timeout = cfg.lockAfterSeconds;
              # Let video playback and other idle inhibitors defer automatic locking.
              ignore_inhibit = false;
              on-timeout = "loginctl lock-session";
            }
            // screenCondition
          )
          (
            {
              timeout = cfg.displayOffAfterSeconds;
              on-timeout = "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'";
              on-resume = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
            }
            // screenCondition
          )
          {
            # Turn off locked displays even while applications prevent sleep.
            # Retry if the short timeout expires before Hyprlock starts.
            timeout = cfg.lockedDisplayOffAfterSeconds;
            ignore_inhibit = true;
            condition_cmd = "${lib.getExe sessionLock} running";
            condition_retry = 5;
            on-timeout = "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'";
            on-resume = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
          }
          (
            {
              timeout = cfg.suspendAfterSeconds;
              on-timeout = "systemctl suspend";
            }
            // lib.optionalAttrs filterNativeInhibitors {
              condition_cmd = "${lib.getExe inhibitorCheck} suspend";
              condition_retry = 5;
            }
          )
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
