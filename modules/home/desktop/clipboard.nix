{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  writeBashTemplate = myLib.writers.writeBashTemplate { inherit pkgs; };
  cfg = config.desktop.clipboard;
  python = pkgs.python3.withPackages (ps: [ ps.dbus-next ]);
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  hyprBind = key: command: {
    _args = [
      key
      (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON command})")
    ];
  };
  watcher = writeBashTemplate {
    name = "desktop-clipboard-history";
    src = ./scripts/clipboard-history.sh.in;
    dir = "bin";
    replacements = {
      cliphist = lib.getExe pkgs.cliphist;
      wlPaste = lib.getExe' pkgs.wl-clipboard "wl-paste";
    };
  };
  choose = writeBashTemplate {
    name = "desktop-clipboard-choose";
    src = ./scripts/clipboard-choose.sh.in;
    dir = "bin";
    replacements = {
      cliphist = lib.getExe pkgs.cliphist;
      walker = lib.getExe pkgs.walker;
      wlCopy = lib.getExe' pkgs.wl-clipboard "wl-copy";
    };
  };
in
{
  options.desktop.clipboard = {
    enable = lib.mkEnableOption "a bounded Wayland clipboard history";

    wipeOnLock = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Clear clipboard history when the graphical session locks.";
    };

    maxItems = lib.mkOption {
      type = lib.types.ints.between 1 500;
      default = 100;
      description = "Maximum clipboard entries retained on disk.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isLinux;
        message = "desktop.clipboard is supported on Linux only.";
      }
      {
        assertion = config.systemd.user.enable;
        message = "desktop.clipboard requires a systemd user manager to supervise its history and lock listeners.";
      }
    ];

    home.packages = [
      pkgs.wl-clipboard
      pkgs.cliphist
      choose
    ];

    # History is useful, but it must be explicitly bounded. Password managers
    # should use autotype instead of copying credentials into this database.
    xdg.configFile."cliphist/config".source = pkgs.writeText "cliphist-config" (
      lib.generators.toKeyValue { mkKeyValue = lib.generators.mkKeyValueDefault { } " "; } {
        max-items = cfg.maxItems;
        max-store-size = "5MiB";
        max-dedupe-search = 100;
        preview-width = 120;
      }
    );

    systemd.user.services.cliphist = {
      Unit = {
        Description = "Bounded Wayland clipboard history";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${lib.getExe' watcher "desktop-clipboard-history"}";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services.cliphist-lock = lib.mkIf cfg.wipeOnLock {
      Unit = {
        Description = "Clear clipboard history when a user session locks";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${lib.getExe python} ${./scripts/clipboard_lock.py} ${lib.getExe pkgs.cliphist}";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    wayland.windowManager.hyprland.settings.bind =
      lib.mkIf config.wayland.windowManager.hyprland.enable
        (lib.mkAfter [ (hyprBind "SUPER + V" (lib.getExe' choose "desktop-clipboard-choose")) ]);
  };
}
