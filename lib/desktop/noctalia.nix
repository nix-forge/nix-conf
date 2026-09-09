_: {
  mkNoctaliaConfig =
    {
      font,
      paletteName,
      pureBlackDark,
    }:
    {
      storage = {
        key_source = "secret-service";
      };
      theme = {
        mode = "dark";
        source = "custom";
        custom_palette = paletteName;
        pure_black_dark = pureBlackDark;
        templates = {
          # Stylix owns application theming; avoid a second mutable configuration.
          enable_builtin_templates = false;
          enable_community_templates = false;
        };
      };
      shell = {
        font_family = font;
        button_borders = false;
        input_borders = true;
        popup_borders = true;
        card_borders = false;
        popup_shadows = true;
        corner_radius_scale = 1.0;
        time_format = "{:%-I:%M %p}";
        date_format = "%a %b %-d";
        # MPRIS album art uses HTTPS, which offline mode would block too.
        offline_mode = false;
        external_ip_enabled = false;
        telemetry_enabled = false;
        setup_wizard_enabled = false;
        polkit_agent = false;
        launch_apps_as_systemd_services = false;
        launch_apps_custom_command = "uwsm app -- $CMD";
        clipboard_enabled = true;
        clipboard_keep_from_closed_apps = true;
        clipboard_history_max_entries = 50;
        clipboard_confirm_clear_history = true;
        clipboard_auto_paste = "off";
        screen_time_enabled = false;
        shared_gl_context = true;
        animation = {
          enabled = true;
          speed = 1.0;
        };
        shadow = {
          direction = "down";
          alpha = 0.35;
        };
        panel = {
          transparency_mode = "solid";
          borders = true;
          shadow = true;
          list_item_background = false;
          floating_layer = "overlay";
          launcher_placement = "floating";
          clipboard_placement = "floating";
          control_center_placement = "attached";
          session_placement = "attached";
          launcher_position = "center";
          clipboard_position = "center";
          floating_offset = 8;
        };
        launcher = {
          categories = true;
          show_icons = true;
          show_app_origin_indicator = true;
          compact = false;
          app_grid = false;
          show_app_actions = true;
          sort_by_usage = true;
          fetch_exchange_rates = false;
          provider_prefix = "/";
          auto_paste = "off";
          providers = {
            calculator = {
              prefix = "calc";
              global = true;
            };
            emoji = {
              prefix = "emoji";
            };
            session = {
              prefix = "session";
              global = false;
            };
            windows = {
              prefix = "windows";
            };
          };
        };
      };
      bar = {
        order = [ "default" ];
        default = {
          position = "top";
          enabled = true;
          auto_hide = false;
          smart_auto_hide = false;
          reserve_space = true;
          layer = "top";
          thickness = 34;
          background_opacity = 1.0;
          border_width = 0.0;
          shadow = false;
          radius = 0;
          margin_ends = 0;
          margin_edge = 0;
          padding = 16;
          widget_spacing = 8;
          hover_highlight = true;
          font_weight = 500;
          capsule = false;
          start = [
            "launcher"
            "workspaces"
            "active_window"
          ];
          center = [ "clock" ];
          end = [
            "media"
            "notifications"
            "tray"
            "network"
            "bluetooth"
            "volume"
            "nightlight"
            "privacy"
            "control-center"
          ];
        };
      };
      widget = {
        clock = {
          format = "{:%a %b %-d  %-I:%M %p}";
          tooltip_format = "{:%A, %B %-d, %Y}";
        };
        network = {
          show_label = false;
        };
        privacy = {
          hide_inactive = true;
        };
      };
      control_center = {
        sidebar = "compact";
        sidebar_section = "compact";
        width = 680;
        show_shortcut_labels = true;
        show_session_button = true;
        hidden_tabs = [
          "weather"
          "screen-time"
        ];
        calendar = {
          event_date_format = "%a %b %-d";
          event_time_format = "%-I:%M %p";
        };
        shortcuts = [
          { type = "wifi"; }
          { type = "bluetooth"; }
          { type = "nightlight"; }
          { type = "notification"; }
          { type = "session"; }
        ];
      };
      notification = {
        enable_daemon = true;
        show_app_name = true;
        show_actions = true;
        position = "top_right";
        layer = "top";
        background_opacity = 0.98;
        border = true;
        offset_x = 16;
        offset_y = 12;
        max_visible = 3;
        history_retention_hours = 168;
        collapse_on_dismiss = true;
      };
      osd = {
        enabled = true;
        position = "top_center";
        background_opacity = 0.98;
        border = true;
        offset_x = 16;
        offset_y = 52;
        kinds = {
          volume = true;
          volume_output = true;
          volume_input = true;
          brightness = true;
          wifi = true;
          bluetooth = true;
          power_profile = true;
          caffeine = true;
          nightlight = true;
          dnd = true;
          lock_keys = false;
          keyboard_layout = true;
          # Noctalia generates these track-change popups independently of Spotify.
          media = false;
          privacy = true;
        };
      };
      system = {
        monitor = {
          enabled = true;
          cpu_poll_seconds = 5.0;
          gpu_poll_seconds = 10.0;
          memory_poll_seconds = 5.0;
          network_poll_seconds = 5.0;
          disk_poll_seconds = 30.0;
        };
      };
      dock = {
        enabled = false;
      };
      wallpaper = {
        # Awww remains the wallpaper renderer and source manager.
        enabled = false;
      };
      desktop_widgets = {
        enabled = false;
      };
      lockscreen = {
        # Hyprlock remains the session-lock authority.
        enabled = false;
      };
      lockscreen_widgets = {
        enabled = false;
      };
      weather = {
        enabled = false;
      };
    };
}
