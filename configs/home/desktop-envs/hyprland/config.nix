{ lib, ... }:
{
  wayland.windowManager.hyprland.settings = {
    # <https://wiki.hyprland.org/Configuring/Variables/#general>
    general = {
      border_size = 2;
      # gaps_in = 5;
      # gaps_out = 10;
      gaps_in = 0;
      gaps_out = 0;
      "col.active_border" = lib.mkForce "rgb(0e5a94)"; # overriden by stylix
      "col.inactive_border" = lib.mkForce "rgb(505050)"; # overriden by stylix
      # no_cursor_warps = true;
      resize_on_border = true;
      extend_border_grab_area = 10;
    };

    # <https://wiki.hyprland.org/Configuring/Variables/#decoration>
    decoration = {
      rounding = 0;
      # shadow_range = 8;
      # shadow_render_power = 2;
      # "col.shadow" = lib.mkForce null;
      # "col.shadow_inactive" = "rgba(00000044)";
      # blur = {
      #   size = 3; # 8
      #   passes = 2; # 1
      #   ignore_opacity = true; # false
      #   xray = true; # false
      #   noise = 6.5e-2; # 0.0117
      #   contrast = 0.75; # 0.8916
      #   brightness = 0.8; # 0.8172
      # };
    };

    # <https://wiki.hyprland.org/Configuring/Variables/#input>
    input =
      let
        DISABLED = 0;
        LOOSE = 2;
      in
      {
        follow_mouse = LOOSE;
        float_switch_override_focus = DISABLED;
      };

    # <https://wiki.hyprland.org/Configuring/Variables/#binds>
    binds =
      let
        LONGEST_SHARED_SIDE = 1;
      in
      {
        focus_preferred_method = LONGEST_SHARED_SIDE;
      };

    gestures = {
      workspace_swipe = true;
      workspace_swipe_invert = false;
      workspace_swipe_min_speed_to_force = 20;
      workspace_swipe_cancel_ratio = 0.65;
      workspace_swipe_create_new = false;
      workspace_swipe_forever = true;
    };

    # <https://wiki.hyprland.org/Configuring/Variables/#misc>
    misc = {
      # disable_hyprland_logo = true; # false
      # disable_splash_rendering = true; # false
      force_default_wallpaper = 0; # set to the base wallpaper
      vfr = true;
      vrr = 0; # 0 - off, 1 - on, 2 - fullscreen only [0/1/2]

      # works well with idle checks
      key_press_enables_dpms = true;
      mouse_move_enables_dpms = true;
    };

    # <https://wiki.hyprland.org/Configuring/Dwindle-Layout/>
    dwindle =
      let
        ALWAYS_EAST = 2;
      in
      {
        force_split = ALWAYS_EAST; # 0
        preserve_split = true; # false
        # no_gaps_when_only = true;
      };

    # Remove popups
    ecosystem = {
      no_update_news = false;
      no_donation_nag = false;
    };

    # Experimental Settings (Subject to Change)
    experimental = {
      wide_color_gamut = true;
    };
  };
}
