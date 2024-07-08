{ lib, ... }:
{
  wayland.windowManager.hyprland = {
    # <https://wiki.hyprland.org/Configuring/Variables/#general>
    settings.general = {
      border_size = 2;
      # gaps_in = 5;
      # gaps_out = 10;
      gaps_in = 0;
      gaps_out = 0;
      "col.active_border" = lib.mkForce "0xffd3c6aa"; # overriden by stylix
      "col.inactive_border" = lib.mkForce "0xff56635f"; # overriden by stylix
      # no_cursor_warps = true;
      resize_on_border = true;
      extend_border_grab_area = 10;
    };

    # <https://wiki.hyprland.org/Configuring/Variables/#decoration>
    settings.decoration = {
      rounding = 0;
      shadow_range = 8;
      shadow_render_power = 2;
      # "col.shadow" = "rgba(00000044)";
      # "col.shadow_inactive" = "rgba(00000044)";
      blur = {
        size = 3; # 8
        passes = 2; # 1
        ignore_opacity = true; # false
        xray = true; # false
        noise = 6.5e-2; # 0.0117
        contrast = 0.75; # 0.8916
        brightness = 0.8; # 0.8172
      };
    };

    # <https://wiki.hyprland.org/Configuring/Variables/#input>
    settings.input =
      let
        DISABLED = 0;
        LOOSE = 2;
      in
      {
        follow_mouse = LOOSE;
        float_switch_override_focus = DISABLED;
      };

    # <https://wiki.hyprland.org/Configuring/Variables/#binds>
    settings.binds =
      let
        LONGEST_SHARED_SIDE = 1;
      in
      {
        focus_preferred_method = LONGEST_SHARED_SIDE;
      };

    settings.gestures = {
      workspace_swipe = true;
      workspace_swipe_invert = false;
      workspace_swipe_min_speed_to_force = 20;
      workspace_swipe_cancel_ratio = 0.65;
      workspace_swipe_create_new = false;
      workspace_swipe_forever = true;
    };

    # <https://wiki.hyprland.org/Configuring/Variables/#misc>
    settings.misc = {
      # disable_hyprland_logo = true; # false
      # disable_splash_rendering = true; # false
      force_default_wallpaper = 0; # set to the base wallpaper
      vfr = true;
      vrr = 0; # 0 - off, 1 - on, 2 - fullscreen only [0/1/2]

      # works well with swayidle
      key_press_enables_dpms = true;
      mouse_move_enables_dpms = true;
    };

    # <https://wiki.hyprland.org/Configuring/Dwindle-Layout/>
    settings.dwindle =
      let
        ALWAYS_EAST = 2;
      in
      {
        force_split = ALWAYS_EAST; # 0
        preserve_split = true; # false
        # no_gaps_when_only = true;
      };

    settings.animations = {
      # bezier = [
      #   "easeInBack, 0.360000, 0, 0.660000, -0.560000"
      #   "easeInCirc, 0.550000, 0, 1, 0.450000"
      #   "easeInCubic, 0.320000, 0, 0.670000, 0"
      #   "easeInExpo, 0.700000, 0, 0.840000, 0"
      #   "easeInOutBack, 0.680000, -0.600000, 0.320000, 1.600000"
      #   "easeInOutCirc, 0.850000, 0, 0.150000, 1"
      #   "easeInOutCubic, 0.650000, 0, 0.350000, 1"
      #   "easeInOutExpo, 0.870000, 0, 0.130000, 1"
      #   "easeInOutQuad, 0.450000, 0, 0.550000, 1"
      #   "easeInOutQuart, 0.760000, 0, 0.240000, 1"
      #   "easeInOutQuint, 0.830000, 0, 0.170000, 1"
      #   "easeInOutSine, 0.370000, 0, 0.630000, 1"
      #   "easeInQuad, 0.110000, 0, 0.500000, 0"
      #   "easeInQuart, 0.500000, 0, 0.750000, 0"
      #   "easeInQuint, 0.640000, 0, 0.780000, 0"
      #   "easeInSine, 0.120000, 0, 0.390000, 0"
      #   "easeOutBack, 0.340000, 1.560000, 0.640000, 1"
      #   "easeOutCirc, 0, 0.550000, 0.450000, 1"
      #   "easeOutCubic, 0.330000, 1, 0.680000, 1"
      #   "easeOutExpo, 0.160000, 1, 0.300000, 1"
      #   "easeOutQuad, 0.500000, 1, 0.890000, 1"
      #   "easeOutQuart, 0.250000, 1, 0.500000, 1"
      #   "easeOutQuint, 0.220000, 1, 0.360000, 1"
      #   "easeOutSine, 0.610000, 1, 0.880000, 1"
      #   "linear, 0, 0, 1, 1"
      # ];

      # animation = [
      #   "fadeIn, 1, 1, easeOutCirc"
      #   "fadeOut, 1, 1, easeOutCirc"
      #   "windowsIn, 1, 2, easeOutCirc, popin 60%"
      #   "windowsMove, 1, 3, easeInOutCubic, popin"
      #   "windowsOut, 1, 2, easeOutCirc, popin 60%"
      #   "workspaces, 1, 2, easeOutCirc, slide"
      # ];
    };
  };
}
