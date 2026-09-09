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
      bash = lib.getExe pkgs.bash;
      cliphist = lib.getExe pkgs.cliphist;
      wlPaste = lib.getExe' pkgs.wl-clipboard "wl-paste";
    };
  };
  choose = writeBashTemplate {
    name = "desktop-clipboard-choose";
    src = ./scripts/clipboard-choose.sh.in;
    dir = "bin";
    replacements = {
      bash = lib.getExe pkgs.bash;
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

    wayland.windowManager.hyprland.settings.bind =
      lib.mkIf config.wayland.windowManager.hyprland.enable
        (lib.mkAfter [ (hyprBind "SUPER + V" (lib.getExe' choose "desktop-clipboard-choose")) ]);
  };
}
