{
  config,
  lib,
  myLib,
  pkgs,
  self,
  system,
  ...
}:
let
  desktopLib = myLib.desktop;
  cfg = config.desktop.noctalia;
  colors = config.lib.stylix.colors.withHashtag;
  isOled = config.appearance.theme == "carbon-neon-oled";
  noctalia = lib.getExe config.programs.noctalia.package;
  darkAppIcons = self.packages.${system}.noctalia-dark-app-icons;
  syncAppIcons = pkgs.writeShellApplication {
    name = "noctalia-sync-app-icons";
    runtimeInputs = [ pkgs.glib ];
    text = ''
      mode="''${NOCTALIA_THEME_MODE:-}"
      if [[ -z "$mode" ]]; then
        mode="$(${noctalia} msg theme-mode-get)"
      fi
      case "$mode" in
        dark) theme=${lib.escapeShellArg darkAppIcons.iconThemeName} ;;
        light) theme=${lib.escapeShellArg config.stylix.icons.light} ;;
        *) echo "Unknown Noctalia theme mode: $mode" >&2; exit 1 ;;
      esac
      gsettings set org.gnome.desktop.interface icon-theme "$theme"
    '';
  };
  featureSettings = {
    widget = lib.optionalAttrs cfg.symbolicBarIcons.enable {
      active_window.symbolic_icons = true;
      taskbar.symbolic_icons = true;
      tray.icon_overrides = cfg.symbolicBarIcons.trayOverrides;
    };
    hooks = lib.optionalAttrs cfg.darkAppIcons.enable {
      started = [ (lib.getExe syncAppIcons) ];
      theme_mode_changed = [ (lib.getExe syncAppIcons) ];
    };

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
      icon_size = 42;
      # Keep artwork at full opacity and size regardless of window focus.
      # Running dots and hover magnification provide the state feedback.
      active_opacity = 1.0;
      inactive_opacity = 1.0;
      active_scale = 1.0;
      inactive_scale = 1.0;
      main_axis_padding = 12;
      cross_axis_padding = 6;
      item_spacing = 4;
      background_opacity = 0.96;
      radius = 14;
      margin_edge = 10;
      shadow = false;
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
    home.packages = lib.optional cfg.darkAppIcons.enable darkAppIcons;
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
      style = pkgs.replaceVarsWith {
        src = ./config/hyprshell.css.in;
        postCheck = ''
          ${desktopLib.mkGtkCssChecker { inherit pkgs; }}/bin/check-gtk-css "$target"
        '';
        replacements = {
          inherit (colors)
            base00
            base01
            base02
            base03
            base05
            base0D
            ;
          font = builtins.toJSON config.stylix.fonts.sansSerif.name;
        };
      };
    };

    # This module derives its complete palette and settings from Stylix below.
    # Disable the upstream adapter so it cannot also define palette or opacity.
    stylix.targets.noctalia.enable = false;

    programs.noctalia = {
      enable = true;
      package = self.packages.${system}.noctalia-personal;
      systemd.enable = true;
      settings = desktopLib.mkNoctaliaConfig {
        font = config.stylix.fonts.sansSerif.name;
        paletteName = "Stylix";
        pureBlackDark = isOled;
      };
      customPalettes.Stylix = desktopLib.mkNoctaliaPalette { inherit colors; };
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
    xdg.dataFile =
      lib.mapAttrs' (
        name: source: lib.nameValuePair "noctalia/plugins/${name}" { inherit source; }
      ) cfg.plugins
      // lib.optionalAttrs cfg.darkAppIcons.enable {
        "icons/${darkAppIcons.iconThemeName}".source =
          "${darkAppIcons}/share/icons/${darkAppIcons.iconThemeName}";
      };

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
