{
  render =
    {
      font,
      fontSizes,
      paletteName,
      pureBlackDark,
    }:
    let
      # Stylix sizes are points; Noctalia's body text is 14 logical pixels.
      # Output DPI scaling is handled by Noctalia, separately from these ratios.
      desktopScale = (fontSizes.desktop * 4.0 / 3.0) / 14.0;
      popupScale = fontSizes.popups * 1.0 / fontSizes.desktop;
    in
    {
      accessibility.ui_scale = desktopScale;
      theme = {
        mode = "dark";
        source = "custom";
        custom_palette = paletteName;
        pure_black_dark = pureBlackDark;

      };

      shell = {
        font_family = font;
        button_borders = false;
        input_borders = true;
        popup_borders = true;
        card_borders = false;
        popup_shadows = true;
        corner_radius_scale = 1.0;
        shadow = {
          direction = "down";
          alpha = 0.35;
        };

        panel = {
          transparency_mode = "solid";
          borders = true;
          shadow = true;
          list_item_background = false;
        };
      };
      bar.default = {
        # Keep status glyphs and workspace artwork in 16px logical boxes.
        scale = 1.0;
        font_scale = desktopScale;
        font_family = font;
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
      };
      # Stable opaque surfaces keep popup contrast independent of the wallpaper.
      notification = {
        scale = popupScale;
        background_opacity = 1.0;
        border = true;
      };
      osd = {
        scale = popupScale;
        background_opacity = 1.0;
        border = true;
      };
      widget = {
        taskbar = {
          icon_scale = 1.0;
          active_opacity = 1.0;
          inactive_opacity = 1.0;
          occupied_color = "on_surface_variant";
          color = "on_surface";
          capsule_radius = 6;
        };
        tray = {
          icon_color = "on_surface";
          match_adjacent_spacing = true;
        };
      };
    };
}
