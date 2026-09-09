{
  homeManager =
    { config, lib, ... }:
    let
      cfg = config.stylix.targets.hyprlock;
      colors = config.lib.stylix.colors;
    in
    {
      key = "nix-conf/stylix/hyprlock/homeManager";
      _file = __curPos.file;
      options.stylix.targets.hyprlock.custom.enable =
        lib.mkEnableOption "the desktop Hyprlock styling"
        // {
          default = true;
        };
      config =
        lib.mkIf
          (config.stylix.enable && cfg.enable && cfg.custom.enable && config.programs.hyprlock.enable)
          {
            programs.hyprlock.settings = {
              background.monitor = "";
              "input-field" = {
                size = "420, 64";
                rounding = 14;
                outline_thickness = 2;
                dots_size = 0.2;
                dots_spacing = 0.2;
                dots_center = true;
                outer_color = lib.mkIf cfg.colors.enable (lib.mkForce "rgb(${colors.base0D})");
                inner_color = lib.mkIf cfg.colors.enable (lib.mkForce "rgb(${colors.base01})");
                font_family = config.stylix.fonts.sansSerif.name;
              };
            };
          };
    };
}
