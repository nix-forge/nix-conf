{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.notifications;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
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

    xdg.configFile."swaync/config.json".text = builtins.toJSON {
      positionX = "right";
      positionY = "top";
      "control-center-positionX" = "right";
      "control-center-positionY" = "top";
      "control-center-width" = 420;
      "control-center-height" = 620;
      "control-center-margin-top" = 42;
      "control-center-margin-right" = 12;
      "notification-icon-size" = 48;
      "notification-body-image-height" = 140;
      "notification-body-image-width" = 240;
      "notification-inline-replies" = true;
      "notification-grouping" = true;
      "image-visibility" = "when-available";
      timeout = 8;
      "timeout-low" = 5;
      "timeout-critical" = 0;
      widgets = [
        "title"
        "dnd"
        "notifications"
        "mpris"
        "volume"
        "backlight"
      ];
      "widget-config" = {
        title = {
          text = "Notifications";
          "clear-all-button" = true;
        };
        dnd = {
          text = "Do not disturb";
        };
        mpris = {
          "image-size" = 96;
          "image-radius" = 8;
        };
        volume = {
          label = "Volume";
        };
        backlight = {
          label = "Brightness";
        };
      };
    };

    xdg.configFile."swaync/style.css".source = pkgs.replaceVarsWith {
      name = "swaync-desktop-style";
      src = ./config/swaync.css;
      replacements = { };
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
