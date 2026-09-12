{
  nixos =
    { config, lib, ... }:
    let
      design = (import ./design.nix).render { inherit config; };
    in
    {
      key = "nix-conf/stylix/authentication/nixos";
      config = lib.mkIf (config.stylix.enable && config.services.displayManager.noctalia-greeter.enable) {
        services.displayManager.noctalia-greeter = {
          cursorTheme = {
            inherit (config.stylix.cursor) package name;
          };
          settings = {
            appearance = {
              scheme = "Synced";
              theme_mode = "dark";
              font_family = design.font;
              font_scale = design.fontScale;
              password_style = "default";
              hide_logo = true;
              scheme_selector_position = "hidden";
              power_buttons_position = "bottom-right";
              corner_radius_scale = 1.0;
              panel_width = design.panelWidth;
              input_height = design.inputHeight;
              clock_time_format = design.timeFormat;
              clock_date_format = design.dateFormat;
              palette = design.greeterPalette;
              wallpaper.path = "color:${design.colors.base00}";
            };
            cursor.size = config.stylix.cursor.size;
          };
        };
      };
    };
}
