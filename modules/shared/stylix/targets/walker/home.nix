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
      key = "nix-conf/stylix/walker/homeManager";
      _file = __curPos.file;
      options.stylix.targets.walker.enable = config.lib.stylix.mkEnableTarget "walker" true;
      config = lib.optionalAttrs (options ? desktop.walker) (
        lib.mkIf
          (config.stylix.enable && config.stylix.targets.walker.enable && config.desktop.walker.enable)
          {
            desktop.walker.settings.theme = lib.mkDefault "stylix";
            xdg.configFile."walker/themes/stylix/style.css".source = pkgs.replaceVarsWith {
              name = "walker-style.css";
              src = ./walker-style.css.in;
              postCheck = ''
                ${desktopLib.mkGtkCssChecker { inherit pkgs; }}/bin/check-gtk-css "$target"
              '';
              replacements = {
                font = builtins.toJSON config.stylix.fonts.sansSerif.name;
                inherit (colors)
                  base00
                  base01
                  base02
                  base03
                  base04
                  base05
                  base08
                  base09
                  base0A
                  base0B
                  base0D
                  ;
              };
            };
          }
      );
    };
}
