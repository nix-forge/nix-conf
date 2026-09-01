{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.bar;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  json = builtins.toJSON {
    layer = "top";
    position = "top";
    height = 30;
    spacing = 8;
    "modules-left" = [
      "hyprland/workspaces"
      "hyprland/window"
    ];
    "modules-center" = [ "clock" ];
    "modules-right" = [
      "wireplumber"
      "network"
      "bluetooth"
      "battery"
      "power-profiles-daemon"
      "tray"
    ];
    "hyprland/workspaces" = {
      "all-outputs" = false;
      "disable-scroll" = true;
      format = "{name}";
    };
    "hyprland/window" = {
      "max-length" = 80;
      "separate-outputs" = true;
    };
    clock = {
      format = "{:%a %b %d  %H:%M}";
      "tooltip-format" = "<big>{:%B %Y}</big>\n<tt><small>{calendar}</small></tt>";
    };
    wireplumber = {
      format = "{icon} {volume}%";
      "format-muted" = "Muted";
      "format-icons" = [
        "Volume"
        "Volume"
        "Volume"
      ];
      "on-click" = "pwvucontrol";
      "on-click-right" = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
    };
    network = {
      format-wifi = "Wi-Fi {signalStrength}%";
      format-ethernet = "Wired";
      format-disconnected = "Offline";
      tooltip-format = "{ifname}: {ipaddr}/{cidr}";
      "on-click" = cfg.networkCommand;
    };
    bluetooth = {
      format = "Bluetooth";
      "format-disabled" = "Bluetooth off";
      "format-connected" = "Bluetooth {device_alias}";
      "on-click" = "blueman-manager";
    };
    battery = {
      states.warning = 30;
      states.critical = 15;
      format = "{capacity}%";
      "format-charging" = "Charging {capacity}%";
      "format-plugged" = "AC {capacity}%";
    };
    "power-profiles-daemon" = {
      format = "{icon}";
      "tooltip-format" = "Power profile: {profile}";
      "format-icons" = {
        default = "Balanced";
        performance = "Performance";
        power-saver = "Saver";
      };
    };
    tray = {
      "icon-size" = 16;
      spacing = 8;
    };
  };
in
{
  options.desktop.bar = {
    enable = lib.mkEnableOption "a low-overhead Waybar desktop panel";

    networkCommand = lib.mkOption {
      type = lib.types.str;
      default = "nm-connection-editor";
      description = "Command that opens the host's network-management UI.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isLinux;
        message = "desktop.bar is supported on Linux only.";
      }
    ];

    home.packages = [ pkgs.pwvucontrol ];

    programs.waybar = {
      enable = true;
      systemd.enable = true;
      settings.mainBar = builtins.fromJSON json;
      style = builtins.readFile (
        pkgs.replaceVarsWith {
          name = "waybar-desktop-style";
          src = ./config/waybar.css;
          replacements = { };
        }
      );
    };
  };
}
