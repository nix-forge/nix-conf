{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  cursor = config.stylix.cursor;
  colors = config.lib.stylix.colors;
  hyprlockPackage = if osConfig != null then osConfig.programs.hyprlock.package else pkgs.hyprlock;
  monitor = "desc:ASUSTek COMPUTER INC PG32UCWM";
in
{
  # Match the monitor by its EDID make/model prefix so the rule survives using
  # a different DisplayPort socket. The 31.5-inch panel is about 140 PPI, so
  # the shared scaling module resolves its physical dimensions to 1.5x. That
  # produces a 2560x1440 logical desktop while driving every native pixel.
  # The alternate 1080p/480 Hz mode remains an explicit gaming choice because
  # it needs a different scale and should not replace the sharp desktop mode.
  wayland.windowManager.hyprland = {
    displayScaling = {
      enable = true;
      displays.${monitor} = {
        mode = "3840x2160@240";
        position = "0x0";
        resolution = {
          width = 3840;
          height = 2160;
        };
        # ASUS specifies a 696.58 x 391.82 mm visible area. The option takes
        # whole millimetres; rounding each dimension preserves the 140 PPI
        # result and therefore the intended conventional 1.5 scale.
        physicalSizeMm = {
          width = 697;
          height = 392;
        };
      };

      # A 16px logical cursor resolves to 24 physical pixels at 1.5x. The
      # generic module exports that size to native Wayland apps, XWayland,
      # GTK, Qt, Chromium, Stylix, and the UWSM session.
      cursor = {
        enable = true;
        logicalSize = 16;
        referenceOutput = monitor;
      };
    };

    # Hyprland's Lua API applies the ordinary compositor settings through one
    # `hl.config` table.  Keeping the table under this Nix option makes Home
    # Manager generate that API call correctly.
    settings.config = {
      # Steam still uses XWayland. Keep its buffers at native pixels so the
      # compositor does not resample text at the output's fractional scale.
      # Steam supplies its matching UI scale through the NixOS package wrapper.
      xwayland.force_zero_scaling = true;

      general = {
        border_size = 1;
        gaps_in = 8;
        gaps_out = 16;
        "col.active_border" = lib.mkForce "rgb(${colors.base0D})";
        "col.inactive_border" = lib.mkForce "rgb(${colors.base02})";
        resize_on_border = true;
      };

      decoration = {
        rounding = 16;
        rounding_power = 2;
        active_opacity = 1.0;
        inactive_opacity = 1.0;
        shadow = {
          enabled = true;
          range = 12;
          render_power = 3;
        };
        blur = {
          enabled = false;
        };
      };
      animations.enabled = true;
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
      binds = {
        workspace_back_and_forth = true;
        allow_workspace_cycles = true;
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

  desktop.hdr = {
    enable = true;
    output = monitor;
    mode = "3840x2160@240";
    position = "0x0";
    scale = 1.5;
    colorManagement = "auto";
    autoHdr = 1;
    vrr = 2;
  };

  # Keep the authentication surface declarative so Home Manager renders the
  # native Hyprlock configuration and can validate its Nix structure.
  programs.hyprlock = {
    enable = true;
    package = hyprlockPackage;
    settings = {
      general = {
        hide_cursor = true;
        ignore_empty_input = true;
        immediate_render = true;
      };

      background = {
        monitor = "";
        color = lib.mkForce "rgb(${colors.base00})";
      };

      "input-field" = {
        monitor = "";
        size = "420, 64";
        rounding = 14;
        outline_thickness = 2;
        dots_size = 0.2;
        dots_spacing = 0.2;
        dots_center = true;
        outer_color = lib.mkForce "rgb(${colors.base0D})";
        inner_color = lib.mkForce "rgb(${colors.base01})";
        font_color = lib.mkForce "rgb(${colors.base05})";
        font_family = config.stylix.fonts.sansSerif.name;
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
