{
  homeManager =
    {
      config,
      lib,
      pkgs,
      myLib,
      ...
    }:
    let
      colors = config.lib.stylix.colors.withHashtag;
      desktopLib = myLib.desktop;
    in
    {
      key = "nix-conf/stylix/hyprshell/homeManager";
      _file = __curPos.file;
      options.stylix.targets.hyprshell.enable = config.lib.stylix.mkEnableTarget "Hyprshell" true;
      config =
        lib.mkIf
          (config.stylix.enable && config.stylix.targets.hyprshell.enable && config.services.hyprshell.enable)
          {
            services.hyprshell = {
              style = pkgs.replaceVarsWith {
                src = ./hyprshell.css.in;
                postCheck = ''
                  ${desktopLib.mkGtkCssChecker { inherit pkgs; }}/bin/check-gtk-css "$target"
                '';
                replacements = {
                  inherit (colors)
                    base00
                    base01
                    base02
                    base03
                    base05
                    base0D
                    ;
                  font = builtins.toJSON config.stylix.fonts.sansSerif.name;
                };
              };
            };
          };
    };
}
