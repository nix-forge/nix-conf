{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.noctalia;
  colors = config.lib.stylix.colors.withHashtag;
  isOled = config.appearance.theme == "carbon-neon-oled";
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
      icon_size = 42;
      main_axis_padding = 12;
      cross_axis_padding = 6;
      item_spacing = 4;
      background_opacity = 0.96;
      radius = 14;
      margin_edge = 10;
      shadow = false;
      show_running = true;
      smart_auto_hide = true;
      reserve_space = false;
      layer = "overlay";
      magnification = false;
      show_dots = true;
      show_instance_count = true;
      active_monitor_only = true;
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
      Noctalia as the single owner of the desktop's visible shell surfaces
    '';

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
      enable = lib.mkEnableOption "a compact, smart-auto-hidden Noctalia dock";

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
    programs.noctalia = {
      enable = true;
      systemd.enable = true;
      settings = pkgs.replaceVarsWith {
        name = "noctalia-stylix-config";
        src = ./config/noctalia.toml.in;
        replacements = {
          font = config.stylix.fonts.sansSerif.name;
          paletteName = "Stylix";
          pureBlackDark = if isOled then "true" else "false";
        };
      };
      customPalettes.Stylix = pkgs.replaceVarsWith {
        name = "noctalia-stylix-palette";
        src = ./config/noctalia-carbon-neon.json.in;
        replacements = {
          inherit (colors)
            base00
            base01
            base02
            base03
            base04
            base05
            base06
            base08
            base0A
            base0B
            base0C
            base0D
            base0E
            ;
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
      After = [ "graphical-session.target" ];
    };

    wayland.windowManager.hyprland.settings.bind = lib.mkAfter [
      (hyprBind "SUPER + SPACE" "${noctalia} msg panel-toggle launcher")
      (hyprBind "SUPER + RETURN" "${noctalia} msg panel-toggle launcher")
      (hyprBind "SUPER + V" "${noctalia} msg panel-toggle clipboard")
      (hyprBind "SUPER + S" "${noctalia} msg panel-toggle control-center")
      (hyprBind "SUPER + COMMA" "${noctalia} msg settings-toggle")
      (hyprBind "ALT + TAB" "${noctalia} msg window-switcher")
      (hyprBind "XF86AudioRaiseVolume" "${noctalia} msg volume-up")
      (hyprBind "XF86AudioLowerVolume" "${noctalia} msg volume-down")
      (hyprBind "XF86AudioMute" "${noctalia} msg volume-mute")
      (hyprBind "XF86AudioMicMute" "${noctalia} msg mic-mute")
      (hyprBind "XF86MonBrightnessUp" "${noctalia} msg brightness-up")
      (hyprBind "XF86MonBrightnessDown" "${noctalia} msg brightness-down")
      (hyprBind "XF86AudioPlay" "${noctalia} msg media toggle")
      (hyprBind "XF86AudioNext" "${noctalia} msg media next")
      (hyprBind "XF86AudioPrev" "${noctalia} msg media previous")
    ];
  };
}
