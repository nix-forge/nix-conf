{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  macShortcuts = config.keyboard.macosShortcuts.enable or false;
  desktopMod = if macShortcuts then "CTRL + ALT + SUPER" else "SUPER";
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
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      @cliphist@ wipe
      @wlPaste@ --type text --watch @cliphist@ store &
      text_watcher=$!
      @wlPaste@ --type image --watch @cliphist@ store &
      image_watcher=$!
      trap 'kill "$text_watcher" "$image_watcher"' EXIT INT TERM
      wait
    '';
    dir = "bin";
    replacements = {
      cliphist = lib.getExe pkgs.cliphist;
      wlPaste = lib.getExe' pkgs.wl-clipboard "wl-paste";
    };
  };
  choose = writeBashTemplate {
    name = "desktop-clipboard-choose";
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      @cliphist@ list | @walker@ --dmenu --prompt 'Clipboard> ' | @cliphist@ decode | @wlCopy@
    '';
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
        ExecStart = "${
          lib.getExe (import ../../../flake/runtime-packages.nix { inherit pkgs; }).clipboardObserver
        } ${lib.getExe pkgs.cliphist}";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    wayland.windowManager.hyprland.settings.bind =
      lib.mkIf config.wayland.windowManager.hyprland.enable
        (lib.mkAfter [ (hyprBind "${desktopMod} + V" (lib.getExe' choose "desktop-clipboard-choose")) ]);
  };
}
