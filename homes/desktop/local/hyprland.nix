{
  config,
  lib,
  pkgs,
  ...
}:
let
  cursor = config.stylix.cursor;
  colors = config.lib.stylix.colors;
in
{
  # This host has no physical monitor.  The virtual output is created by the
  # host's Sunshine service, and this matching rule keeps its logical desktop
  # at the MacBook Pro client's 2562x1656/120 streaming mode. This mode is
  # within 0.13% of the existing stream's pixel count and divides exactly at
  # the MacBook-matched 1.5 scale. Keep this in lockstep with the
  # host-local Sunshine headless-output service so a Hyprland reload does not
  # downgrade an active Moonlight stream.
  wayland.windowManager.hyprland = {
    displayScaling = {
      enable = true;
      displays.SUNSHINE = {
        mode = "2562x1656@120";
        position = "0x0";
        # The stream is a 75%-sized rendering of the MacBook Pro 16-inch
        # panel (3456x2234 at 254 PPI), not a panel with its own EDID. An
        # explicit 1.5 scale therefore preserves the MacBook's near-2x UI
        # density after Moonlight presents the stream at native panel size.
        # Its real panel dimensions must not be supplied to the generic
        # DPI-derived path because that path correctly treats an output's
        # configured pixels as physical pixels.
        resolution = {
          width = 2562;
          height = 1656;
        };
        scale = 1.5;
      };

      # Moonlight upscales this 2562px stream to the MacBook's 3456px Retina
      # panel. A 16px logical cursor therefore resolves to a 24px stream
      # bitmap at 1.5x, or about 16 macOS points after that upscale. The
      # generic module exports this value consistently to Home Manager,
      # Stylix, UWSM, GTK, Qt, Chromium, and XWayland.
      cursor = {
        enable = true;
        logicalSize = 16;
      };
    };

    # Hyprland's Lua API applies the ordinary compositor settings through one
    # `hl.config` table.  Keeping the table under this Nix option makes Home
    # Manager generate that API call correctly.
    settings.config = {
      general = {
        border_size = 2;
        gaps_in = 0;
        gaps_out = 0;
        "col.active_border" = lib.mkForce "rgb(${colors.base0D})";
        "col.inactive_border" = lib.mkForce "rgb(${colors.base02})";
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

  # Keep the authentication surface declarative so Home Manager renders the
  # native Hyprlock configuration and can validate its Nix structure.
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        disable_loading_bar = true;
        grace = 0;
        hide_cursor = true;
        ignore_empty_input = true;
      };

      background = {
        monitor = "";
        color = lib.mkForce "rgb(${colors.base00})";
      };

      "input-field" = {
        monitor = "";
        size = "420, 64";
        outline_thickness = 2;
        dots_size = 0.2;
        dots_spacing = 0.2;
        dots_center = true;
        outer_color = lib.mkForce "rgb(${colors.base0D})";
        inner_color = lib.mkForce "rgb(${colors.base01})";
        font_color = lib.mkForce "rgb(${colors.base05})";
        fade_on_empty = false;
        placeholder_text = "<i>Unlock desktop</i>";
        hide_input = true;
        position = "0, 0";
        halign = "center";
        valign = "center";
      };
    };
  };

  # UWSM loads generic graphical-session variables from `env` and
  # compositor-specific variables from `env-hyprland`, then exports the
  # resulting activation environment to systemd and D-Bus. Keep that split:
  # it makes the session portable while leaving this desktop's NVIDIA device
  # selection in the host-local profile.
  xdg.configFile = {
    "uwsm/env".source = pkgs.replaceVarsWith {
      src = ./config/uwsm-env;
      replacements = {
        cursorTheme = cursor.name;
        cursorSize = toString cursor.size;
      };
    };

    "uwsm/env-hyprland".source = ./config/uwsm-env-hyprland;

  };
}
