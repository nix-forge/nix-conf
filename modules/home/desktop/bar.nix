{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  desktopLib = myLib.desktop;
  cfg = config.desktop.bar;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  colors = config.lib.stylix.colors.withHashtag;
  systemdUtils = import (pkgs.path + "/nixos/lib/utils.nix") {
    inherit lib pkgs;
    config = { };
  };
in
{
  options.desktop.bar = {
    enable = lib.mkEnableOption "a GTK4 Ironbar desktop panel";

    networkCommand = lib.mkOption {
      type = lib.types.str;
      default = "nm-connection-editor";
      description = "Command opened by the panel's network shortcut.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isLinux;
        message = "desktop.bar is supported on Linux only.";
      }
    ];

    # Ironbar replaces Waybar rather than running beside it: one panel avoids
    # duplicate status indicators, tray hosts, and notification affordances.
    programs.waybar.enable = lib.mkForce false;
    home.packages = [ pkgs.ironbar ];

    xdg.configFile = {
      "ironbar/config.toml".source = (pkgs.formats.toml { }).generate "ironbar-config.toml" (
        desktopLib.mkIronbarConfig {
          iconTheme = config.stylix.icons.dark;
          inherit (cfg) networkCommand;
        }
      );

      "ironbar/style.css".source = pkgs.replaceVarsWith {
        name = "ironbar-style";
        src = ./config/ironbar-style.css.in;
        postCheck = ''
          ${desktopLib.mkGtkCssChecker { inherit pkgs; }}/bin/check-gtk-css "$target"
        '';
        replacements = {
          font = builtins.toJSON config.stylix.fonts.sansSerif.name;
          inherit (colors)
            base00
            base01
            base02
            base03
            base04
            base05
            base08
            base09
            base0A
            base0B
            base0D
            ;
        };
      };
    };

    systemd.user.services.ironbar = {
      Unit = {
        Description = "Ironbar GTK4 desktop panel";
        PartOf = [ "graphical-session.target" ];
        After = [
          "graphical-session.target"
          "swaync.service"
        ];
        Wants = [ "swaync.service" ];
      };
      Service = {
        ExecStart = systemdUtils.escapeSystemdExecArgs [
          (lib.getExe pkgs.ironbar)
          "--config"
          "${config.xdg.configHome}/ironbar/config.toml"
          "--theme"
          "${config.xdg.configHome}/ironbar/style.css"
        ];
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
