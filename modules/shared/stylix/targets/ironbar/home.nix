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
      key = "nix-conf/stylix/ironbar/homeManager";
      _file = __curPos.file;
      options.stylix.targets.ironbar.enable = config.lib.stylix.mkEnableTarget "ironbar" true;
      config = lib.optionalAttrs (options ? desktop.bar) (
        lib.mkIf (config.stylix.enable && config.stylix.targets.ironbar.enable && config.desktop.bar.enable)
          {
            desktop.bar.iconTheme = lib.mkDefault config.stylix.icons.dark;
            xdg.configFile."ironbar/style.css".source = pkgs.replaceVarsWith {
              name = "ironbar-style";
              src = ./ironbar-style.css.in;
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
