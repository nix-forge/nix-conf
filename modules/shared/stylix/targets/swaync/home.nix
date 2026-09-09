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

      key = "nix-conf/stylix/swaync/homeManager";

      _file = __curPos.file;

      config = lib.optionalAttrs (options ? desktop.notifications) (
        lib.mkIf
          (config.stylix.enable && config.stylix.targets.swaync.enable && config.desktop.notifications.enable)
          {

            xdg.configFile."swaync/style.css".source = pkgs.replaceVarsWith {
              name = "swaync-desktop-style";
              src = ./swaync-style.css.in;
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
                  base0B
                  base0D
                  ;
              };
            };
          }
      );
    };
}
