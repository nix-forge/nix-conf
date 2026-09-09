{
  homeManager =
    { config, lib, ... }:
    let
      cfg = config.stylix.targets.hyprland;
      colors = config.lib.stylix.colors;
    in
    {
      key = "nix-conf/stylix/hyprland/homeManager";
      _file = __curPos.file;
      options.stylix.targets.hyprland.custom.enable =
        lib.mkEnableOption "the desktop Hyprland styling"
        // {
          default = true;
        };
      config =
        lib.mkIf
          (
            config.stylix.enable
            && cfg.enable
            && cfg.custom.enable
            && config.wayland.windowManager.hyprland.enable
          )
          {
            wayland.windowManager.hyprland.settings.config = {
              general = {
                border_size = lib.mkDefault 1;
                gaps_in = lib.mkDefault 8;
                gaps_out = lib.mkDefault 16;
                "col.active_border" = lib.mkIf cfg.colors.enable (lib.mkForce "rgb(${colors.base0D})");
                "col.inactive_border" = lib.mkIf cfg.colors.enable (lib.mkForce "rgb(${colors.base02})");
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
            };
          };
    };
}
