{
  config,
  lib,
  pkgs,
  myLib,
  osConfig ? null,
  ...
}:
let
  python = pkgs.python3.withPackages (_: [ (myLib.python.notificationProcess { inherit pkgs; }) ]);
  cfg = config.desktop.idle;
  hyprlandPackage = myLib.desktop.resolveHyprlandPackage { inherit config pkgs osConfig; };
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  nixosOwnsHypridle = osConfig != null && (osConfig.services.hypridle.enable or false);
  suspendAllowed =
    osConfig == null
    || (lib.attrByPath [ "systemd" "sleep" "settings" "Sleep" "AllowSuspend" ] "yes" osConfig) != "no";
  sessionLockUnit = "desktop-session-lock";
  sessionClient = pkgs.writeShellApplication {
    name = "${sessionLockUnit}-client";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = (import ../../../lib/templates/text.nix) ./scripts/desktop-session-lock-client.sh {
      pkgs_bash = pkgs.bash;
      scripts_session_lock_sh = ./scripts/session-lock.sh;
      lib_getExe_config_programs_hyprlock_package = lib.getExe config.programs.hyprlock.package;
      lib_escapeShellArg_config_xdg_configHome_hypr_hyprlock_conf = lib.escapeShellArg "${config.xdg.configHome}/hypr/hyprlock.conf";
    };
  };
  sessionLock = pkgs.writeShellApplication {
    name = sessionLockUnit;
    text = (import ../../../lib/templates/text.nix) ./scripts/desktop-session-lock.sh {
      session_client = lib.getExe sessionClient;
      unit_template = lib.escapeShellArg "${sessionLockUnit}@.service";
      ipc_timeout = lib.escapeShellArg "${toString cfg.recoveryIpcTimeoutSeconds}s";
      ipc_kill_after = lib.escapeShellArg "2s";
      systemctl = lib.getExe' pkgs.systemd "systemctl";
      timeout = lib.getExe' pkgs.coreutils "timeout";
      sha256sum = lib.getExe' pkgs.coreutils "sha256sum";
      flock = lib.getExe' pkgs.util-linux "flock";
      systemd_escape = lib.getExe' pkgs.systemd "systemd-escape";
      hyprctl = lib.getExe' hyprlandPackage "hyprctl";
      jq = lib.getExe pkgs.jq;
    };
  };
  hyprctl = lib.getExe' hyprlandPackage "hyprctl";
  loginctl = lib.getExe' pkgs.systemd "loginctl";
  systemctl = lib.getExe' pkgs.systemd "systemctl";
  filterNativeInhibitors = cfg.backgroundAppClasses != [ ];
  inhibitorCheck = pkgs.writeShellApplication {
    name = "desktop-idle-inhibit-check";
    runtimeInputs = [ hyprlandPackage ];
    text = (import ../../../lib/templates/text.nix) ./scripts/desktop-idle-inhibit-check.sh {
      lib_getExe_pkgs_python3 = lib.getExe python;
      scripts_idle_inhibit_check_py = ./scripts/idle_inhibit_check.py;
    };
  };
  screenCondition = lib.optionalAttrs filterNativeInhibitors {
    condition_cmd = "${lib.getExe inhibitorCheck} screen -- ${lib.escapeShellArgs cfg.backgroundAppClasses}";
    condition_retry = 5;
  };
  wipeCommand = lib.optionalString (
    (config.desktop.clipboard.enable or false) && (config.desktop.clipboard.wipeOnLock or false)
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

    recoveryIpcTimeoutSeconds = lib.mkOption {
      type = lib.types.ints.between 1 60;
      default = 5;
      description = "Maximum duration of each compositor call during explicit lock recovery.";
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
        assertion = config.wayland.windowManager.hyprland.enable;
        message = "desktop.idle requires Hyprland for its display power policy.";
      }
      {
        assertion = config.programs.hyprlock.enable;
        message = "desktop.idle requires programs.hyprlock.enable for its session lock.";
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

    programs.hyprlock.enable = lib.mkDefault true;

    # The locker must survive idle-daemon restarts and declarative activation.
    # Display-specific instances preserve independent compositor connections.
    systemd.user.services."${sessionLockUnit}@" = {
      Unit = {
        Description = "Authenticated session lock for %I";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
        X-SwitchMethod = "keep-old";
        # Removing this feature must also preserve an existing password prompt.
        # Dependency-driven graphical-session teardown is still permitted.
        RefuseManualStop = true;
        StartLimitIntervalSec = 30;
        StartLimitBurst = 3;
      };
      Service = {
        Type = "exec";
        Environment = [ "WAYLAND_DISPLAY=%I" ];
        ExecStart = "${lib.getExe sessionClient} lock";
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };

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
          before_sleep_cmd = "${loginctl} lock-session";
          after_sleep_cmd = "${hyprctl} dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
          on_lock_cmd = if onLockCommand == "" then "true" else onLockCommand;
          on_unlock_cmd = "${hyprctl} dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
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
              on-timeout = "${loginctl} lock-session";
            }
            // screenCondition
          )
          (
            {
              timeout = cfg.displayOffAfterSeconds;
              on-timeout = "${hyprctl} dispatch 'hl.dsp.dpms({ action = \"disable\" })'";
              on-resume = "${hyprctl} dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
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
            on-timeout = "${hyprctl} dispatch 'hl.dsp.dpms({ action = \"disable\" })'";
            on-resume = "${hyprctl} dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
          }
        ]
        ++ lib.optional suspendAllowed (
          {
            timeout = cfg.suspendAfterSeconds;
            on-timeout = "${systemctl} suspend";
          }
          // lib.optionalAttrs filterNativeInhibitors {
            condition_cmd = "${lib.getExe inhibitorCheck} suspend";
            condition_retry = 5;
          }
        );
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
        (lib.mkAfter [ (hyprBind "SUPER + L" "${loginctl} lock-session") ]);
  };
}
