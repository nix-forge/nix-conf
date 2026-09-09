{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.bar;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  systemdUtils = import (pkgs.path + "/nixos/lib/utils.nix") {
    inherit lib pkgs;
    config = { };
  };
in
{
  options.desktop.bar = {
    enable = lib.mkEnableOption "a GTK4 Ironbar desktop panel";

    iconTheme = lib.mkOption {
      type = lib.types.str;
      default = "hicolor";
      description = "Icon theme used by the panel.";
    };

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
      "ironbar/config.toml".source = (pkgs.formats.toml { }).generate "ironbar-config.toml" {
        icon_theme = cfg.iconTheme;
        position = "top";
        height = 40;
        anchor_to_edges = true;
        exclusive_zone = true;
        margin = {
          top = 10;
          left = 12;
          right = 12;
          bottom = 0;
        };
        start = [
          {
            type = "menu";
            label = "󰍜";
          }
          { type = "workspaces"; }
          {
            type = "focused";
            show_icon = true;
            show_title = true;
            icon_size = 18;
            truncate = {
              mode = "end";
              max_length = 52;
            };
          }
        ];
        center = [
          {
            type = "clock";
            format = "<b>%a, %b %-d</b>  %H:%M";
            format_popup = "%A, %B %-d\n%H:%M";
          }
        ];
        end = [
          {
            type = "music";
            player_type = "mpris";
          }
          {
            type = "volume";
            format = "{icon} {percentage}%";
            mute_format = "󰝟 Muted";
            show_sources = true;
          }
          {
            type = "custom";
            name = "network";
            class = "network";
            bar = [
              {
                type = "button";
                name = "network-button";
                label = "󰖩";
                on_click = cfg.networkCommand;
              }
            ];
          }
          {
            type = "bluetooth";
            format = {
              disabled = "󰂲";
              enabled = "󰂯";
              connected = "󰂱 {device_alias}";
              connected_battery = "󰂱 {device_battery_percent}%";
            };
          }
          {
            type = "notifications";
            show_count = true;
          }
          { type = "tray"; }
          {
            type = "custom";
            name = "power-menu";
            class = "power-menu";
            bar = [
              {
                type = "button";
                name = "power-button";
                label = "󰐥";
                on_click = "popup:toggle";
              }
            ];
            popup = [
              {
                type = "box";
                orientation = "vertical";
                widgets = [
                  {
                    type = "label";
                    name = "header";
                    label = "Session";
                  }
                  {
                    type = "box";
                    name = "buttons";
                    widgets = [
                      {
                        type = "button";
                        class = "power-action lock";
                        label = "󰌾";
                        on_click = "!loginctl lock-session";
                      }
                      {
                        type = "button";
                        class = "power-action suspend";
                        label = "󰤄";
                        on_click = "!systemctl suspend";
                      }
                      {
                        type = "button";
                        class = "power-action restart";
                        label = "󰜉";
                        on_click = "!systemctl reboot";
                      }
                      {
                        type = "button";
                        class = "power-action shutdown";
                        label = "󰐥";
                        on_click = "!systemctl poweroff";
                      }
                    ];
                  }
                ];
              }
            ];
          }
        ];
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
        ExecStart = systemdUtils.escapeSystemdExecArgs (
          [
            (lib.getExe pkgs.ironbar)
            "--config"
            "${config.xdg.configHome}/ironbar/config.toml"
          ]
          ++ lib.optionals (config.xdg.configFile ? "ironbar/style.css") [
            "--theme"
            "${config.xdg.configHome}/ironbar/style.css"
          ]
        );
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
