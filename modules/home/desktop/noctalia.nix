{
  config,
  lib,
  pkgs,
  self,
  system,
  ...
}:
let
  cfg = config.desktop.noctalia;
  noctalia = lib.getExe config.programs.noctalia.package;
  featureSettings = {
    nightlight = lib.optionalAttrs cfg.nightLight.enable {
      enabled = true;
      force = false;
      temperature_day = cfg.nightLight.dayTemperature;
      temperature_night = cfg.nightLight.nightTemperature;
    };

    location = lib.optionalAttrs cfg.nightLight.enable {
      custom_schedule = true;
      inherit (cfg.nightLight) sunrise sunset;
    };

    brightness = lib.optionalAttrs cfg.brightness.enable (
      {
        enable_ddcutil = cfg.brightness.enableDdcutil;
        minimum_brightness = cfg.brightness.minimum;
      }
      // lib.optionalAttrs (cfg.brightness.disabledOutputs != [ ]) {
        monitor = lib.genAttrs cfg.brightness.disabledOutputs (_: {
          backend = "none";
        });
      }
    );

    dock = lib.optionalAttrs cfg.dock.enable {
      enabled = true;
      position = "bottom";
      show_running = true;
      auto_hide = true;
      smart_auto_hide = false;
      reserve_space = false;
      layer = "overlay";
      magnification = true;
      show_dots = true;
      show_instance_count = true;
      # Include open applications even when their windows are on another
      # workspace or output, as in the macOS Dock.
      active_monitor_only = false;
      inherit (cfg.dock) pinned;
    };
  };
  hyprBind = key: command: {
    _args = [
      key
      (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON command})")
    ];
  };
in
{
  options.desktop.noctalia = {
    enable = lib.mkEnableOption ''
      Noctalia as the desktop shell, with Hyprshell for recent-window switching
    '';

    darkAppIcons.enable = lib.mkEnableOption ''
      dark ChatGPT, Zen and VS Code artwork that follows Noctalia's appearance,
      with the normal icon theme in light mode
    '';

    symbolicBarIcons = {
      enable = lib.mkEnableOption "themed symbolic application icons in the menu bar";
      trayOverrides = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Explicit icon-theme names for stable tray identities whose applications
          supply static bitmaps. Attention images and overlays remain intact.
        '';
      };
    };

    nightLight = {
      enable = lib.mkEnableOption "Noctalia's local, scheduled night light";

      dayTemperature = lib.mkOption {
        type = lib.types.ints.between 1000 6500;
        default = 6500;
        description = "Daylight colour temperature in kelvin.";
      };

      nightTemperature = lib.mkOption {
        type = lib.types.ints.between 1000 6400;
        default = 4200;
        description = "Night colour temperature in kelvin.";
      };

      sunrise = lib.mkOption {
        type = lib.types.strMatching "[0-2][0-9]:[0-5][0-9]";
        default = "06:30";
        description = "Local sunrise time for the privacy-preserving night-light schedule.";
      };

      sunset = lib.mkOption {
        type = lib.types.strMatching "[0-2][0-9]:[0-5][0-9]";
        default = "20:00";
        description = "Local sunset time for the privacy-preserving night-light schedule.";
      };
    };

    brightness = {
      enable = lib.mkEnableOption "Noctalia brightness controls";

      enableDdcutil = lib.mkEnableOption "DDC/CI discovery for verified external displays";

      minimum = lib.mkOption {
        type = lib.types.addCheck lib.types.float (value: value >= 0.0 && value <= 1.0);
        default = 0.05;
        description = "Brightness floor, expressed as a fraction of full brightness.";
      };

      disabledOutputs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "SUNSHINE" ];
        description = "Outputs without a usable brightness backend that Noctalia should hide.";
      };
    };

    dock = {
      enable = lib.mkEnableOption "a compact Noctalia dock that reveals on pointer hover";

      pinned = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "zen"
          "com.mitchellh.ghostty"
        ];
        description = "Desktop-entry IDs pinned in the dock.";
      };
    };

    plugins = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      example = lib.literalExpression ''
        {
          timer = pkgs.fetchFromGitHub {
            owner = "noctalia-dev";
            repo = "official-plugins";
            rev = "<reviewed commit>";
            hash = "sha256-...";
          } + "/timer";
        }
      '';
      description = ''
        Reviewed, immutable plugin directories linked into Noctalia's local
        plugin directory. Plugins are trusted code with filesystem, process,
        environment, clipboard, and network access. Do not add a remote or
        automatically updating source here.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.wayland.windowManager.hyprland.enable;
        message = "desktop.noctalia requires an enabled Hyprland session.";
      }
      {
        assertion = !config.desktop.nightLight.enable || !cfg.nightLight.enable;
        message = "Use either desktop.nightLight or desktop.noctalia.nightLight, not both gamma controllers.";
      }
      {
        assertion =
          !cfg.nightLight.enable || cfg.nightLight.dayTemperature >= cfg.nightLight.nightTemperature + 100;
        message = "desktop.noctalia.nightLight.dayTemperature must exceed nightTemperature by at least 100 K.";
      }
    ];

    # A shell is only coherent when it owns each visible responsibility. Keep
    # the compositor, portal, lock, idle, capture, and wallpaper-acquisition
    # layers independent, but remove the overlapping GTK panel processes.
    desktop = {
      bar.enable = lib.mkForce false;
      launcher.enable = lib.mkForce false;
      notifications.enable = lib.mkForce false;
      osd.enable = lib.mkForce false;
      clipboard.enable = lib.mkForce false;
      idle.onLockCommand = lib.mkDefault "${noctalia} msg clipboard-clear";
    };

    programs.fuzzel.enable = lib.mkForce false;

    # Noctalia's picker orders windows by workspace and position. Alt+Tab
    # needs a stable most-recently-used list and modifier-release handling.
    # Hyprshell installs its own Lua bindings, including Shift+Tab and Escape.
    services.hyprshell = {
      enable = true;
      package = pkgs.hyprshell;
      settings = {
        version = 4;
        windows = {
          scale = 2.0;
          items_per_row = 5;
          overview = null;
          switch = {
            modifier = "alt";
            key = "Tab";
            filter_by = [ ];
            switch_workspaces = false;
          };
        };
      };
    };

    programs.noctalia = {
      enable = true;
      package = self.packages.${system}.noctalia-personal;
      systemd.enable = true;
      settings = {
        theme = {
          templates = {
            # Stylix owns application theming; avoid a second mutable configuration.
            enable_builtin_templates = false;
            enable_community_templates = false;
          };
        };
        storage = {
          key_source = "secret-service";
        };
        shell = {
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
          panel = {
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
    };

    # Noctalia merges every TOML file in this directory. Keeping hardware and
    # optional surfaces in a later file leaves the visual baseline readable
    # while preserving declarative feature switches in this module.
    xdg.configFile."noctalia/zz-nix-desktop-features.toml".source =
      (pkgs.formats.toml { }).generate "noctalia-nix-desktop-features.toml"
        featureSettings;

    # The store links make plugin revisions part of the Home Manager closure.
    # This intentionally supports local reviewed code only, not Noctalia's
    # mutable plugin catalog or a background git updater.
    xdg.dataFile = lib.mapAttrs' (
      name: source: lib.nameValuePair "noctalia/plugins/${name}" { inherit source; }
    ) cfg.plugins;

    # Make the service transition exclusive even before a logout. Home Manager
    # removes the old units on activation; these conflicts also stop a stale
    # process from retaining a second layer-shell surface in the live session.
    systemd.user.services.noctalia.Unit = {
      Conflicts = [
        "ironbar.service"
        "walker.service"
        "elephant.service"
        "swaync.service"
        "swayosd.service"
        "cliphist.service"
      ]
      ++ lib.optional cfg.nightLight.enable "hyprsunset.service";
      After = [
        "graphical-session.target"
        "pipewire.service"
      ];
      # Noctalia 5.0 does not reconnect after PipeWire replaces its socket.
      # Restart the shell after a deliberate PipeWire restart so its device
      # model is rebuilt from the new graph.
      PartOf = [ "pipewire.service" ];
    };

    wayland.windowManager.hyprland.settings.bind = lib.mkAfter [
      (hyprBind "SUPER + SPACE" "${noctalia} msg panel-toggle launcher")
      (hyprBind "SUPER + RETURN" "${noctalia} msg panel-toggle launcher")
      (hyprBind "SUPER + V" "${noctalia} msg panel-toggle clipboard")
      (hyprBind "SUPER + S" "${noctalia} msg panel-toggle control-center")
      (hyprBind "SUPER + COMMA" "${noctalia} msg settings-toggle")
      (hyprBind "XF86AudioRaiseVolume" "${noctalia} msg volume-up")
      (hyprBind "XF86AudioLowerVolume" "${noctalia} msg volume-down")
      (hyprBind "XF86AudioMute" "${noctalia} msg volume-mute")
      (hyprBind "XF86AudioMicMute" "${noctalia} msg mic-mute")
      (hyprBind "XF86MonBrightnessUp" "${noctalia} msg brightness-up")
      (hyprBind "XF86MonBrightnessDown" "${noctalia} msg brightness-down")
      (hyprBind "XF86AudioPlay" "${noctalia} msg media toggle")
      # AirPods can repeat Pause when AVRCP audio activity and the selected
      # player's state differ. Treat either stem event as a playback toggle.
      (hyprBind "XF86AudioPause" "${noctalia} msg media toggle")
      (hyprBind "XF86AudioNext" "${noctalia} msg media next")
      (hyprBind "XF86AudioPrev" "${noctalia} msg media previous")
    ];
  };
}
