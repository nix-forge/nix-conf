{
  homeManager =
    {
      config,
      lib,
      myLib,
      pkgs,
      options,
      ...
    }:
    let
      desktopLib = myLib.desktop;
      colors = config.lib.stylix.colors.withHashtag;
    in
    {
      key = "nix-conf/stylix/swayosd/homeManager";
      _file = __curPos.file;
      options.stylix.targets.swayosd.enable = config.lib.stylix.mkEnableTarget "swayosd" true;
      config = lib.optionalAttrs (options ? desktop.osd) (
        lib.mkIf (config.stylix.enable && config.stylix.targets.swayosd.enable && config.desktop.osd.enable)
          {

            xdg.configFile."swayosd/style.css".source = pkgs.replaceVarsWith {
              name = "swayosd-style";
              src = ./swayosd-style.css.in;
              postCheck = ''
                ${desktopLib.mkGtkCssChecker { inherit pkgs; }}/bin/check-gtk-css "$target"
              '';
              replacements = {
                font = builtins.toJSON config.stylix.fonts.sansSerif.name;
                inherit (colors)
                  base00
                  base03
                  base05
                  base0D
                  ;
              };
            };
          }
      );
    };
}
