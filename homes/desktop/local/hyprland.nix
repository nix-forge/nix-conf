{ config, lib, ... }: {
  # This host has no physical monitor.  The virtual output is created by the
  # host's Sunshine service, and this matching rule keeps its logical desktop
  # at 1080p rather than Hyprland's high-DPI fallback scale.
  wayland.windowManager.hyprland.settings = {
    monitor = [
      {
        output = "SUNSHINE";
        mode = "1920x1080@60";
        position = "0x0";
        scale = 1;
      }
    ];

    # Hyprland's Lua API applies the ordinary compositor settings through one
    # `hl.config` table.  Keeping the table under this Nix option makes Home
    # Manager generate that API call correctly.
    config = {
      general = {
        border_size = 2;
        gaps_in = 0;
        gaps_out = 0;
        "col.active_border" = "rgb(0e5a94)";
        "col.inactive_border" = "rgb(505050)";
        resize_on_border = true;
      };

      decoration.rounding = 0;
      input = {
        follow_mouse = 2;
        float_switch_override_focus = 0;
      };
      misc = {
        force_default_wallpaper = 0;
        vrr = 0;
        key_press_enables_dpms = true;
        mouse_move_enables_dpms = true;
      };
      dwindle = {
        force_split = 2;
        preserve_split = true;
      };
      ecosystem = {
        no_update_news = true;
        no_donation_nag = true;
      };
    };
  };

  # UWSM sources this file before it starts Hyprland.  Keep desktop-specific
  # environment choices beside the desktop profile rather than in a reusable
  # module.
  xdg.configFile."uwsm/env-hyprland".text = lib.concatStringsSep "\n" [
    ''
      export NIXOS_OZONE_WL=1
      export GDK_BACKEND=wayland,x11,*
      export SDL_VIDEODRIVER=wayland,x11,windows
      export CLUTTER_BACKEND=wayland
      export QT_AUTO_SCREEN_SCALE_FACTOR=1
      export QT_QPA_PLATFORM=wayland;xcb
      export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
      export ELECTRON_OZONE_PLATFORM_HINT=auto
      export _JAVA_AWT_WM_NONREPARENTING=1
      export HYPRLAND_NO_SD_VARS=1
      export HYPRLAND_NO_SD_NOTIFY=1
      export MOZ_ENABLE_WAYLAND=1
    ''
    (lib.optionalString
      (config.home.sessionVariables ? IGPU_CARD && config.home.sessionVariables ? DGPU_CARD)
      ''
        export AQ_DRM_DEVICES=${config.home.sessionVariables.IGPU_CARD}:${config.home.sessionVariables.DGPU_CARD}
      ''
    )
  ];
}
