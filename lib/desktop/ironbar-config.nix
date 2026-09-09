_: {
  mkIronbarConfig = { iconTheme, networkCommand }: {
    icon_theme = iconTheme;
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
            on_click = networkCommand;
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
}
