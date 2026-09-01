{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.notifications;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  colors = config.lib.stylix.colors.withHashtag;
  hyprBind = key: command: {
    _args = [
      key
      (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON command})")
    ];
  };
in
{
  options.desktop.notifications.enable = lib.mkEnableOption "SwayNotificationCenter notifications and control centre";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isLinux;
        message = "desktop.notifications is supported on Linux only.";
      }
    ];

    home.packages = [ pkgs.libnotify ];

    xdg.configFile."swaync/config.json".source = pkgs.replaceVarsWith {
      name = "swaync-config";
      src = ./config/swaync-config.json.in;
      replacements = { };
    };

    xdg.configFile."swaync/style.css".source = pkgs.replaceVarsWith {
      name = "swaync-desktop-style";
      src = ./config/swaync-style.css.in;
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
          base0B
          base0D
          ;
      };
    };

    systemd.user.services.swaync = {
      Unit = {
        Description = "SwayNotificationCenter";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.swaynotificationcenter}/bin/swaync";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    wayland.windowManager.hyprland.settings.bind =
      lib.mkIf config.wayland.windowManager.hyprland.enable
        (
          lib.mkAfter [
            (hyprBind "SUPER + N" "${lib.getExe' pkgs.swaynotificationcenter "swaync-client"} -t")
            (hyprBind "SUPER + SHIFT + N" "${lib.getExe' pkgs.swaynotificationcenter "swaync-client"} -d")
          ]
        );
  };
}
