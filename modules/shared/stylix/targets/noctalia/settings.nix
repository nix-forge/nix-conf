{
  render =
    {
      font,
      paletteName,
      pureBlackDark,
    }:
    {
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
    };
}
