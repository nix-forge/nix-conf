{
  homeManager =
    {
      config,
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      fixes = import ../../../../../overlays/temporary { inherit inputs lib; };
      polarity = (import ./resolve-polarity.nix).resolve {
        inherit lib;
        inherit (config.stylix) polarity;
        colors = config.lib.stylix.colors;
      };
    in
    {
      key = "nix-conf/stylix/gtk/homeManager";
      _file = __curPos.file;
      imports = [
        (import ../../profile.nix).homeManager
        (fixes.apply "stylix-gtk-flatpak-polarity" inputs.stylix)
      ];
      config =
        lib.mkIf
          (
            pkgs.stdenv.hostPlatform.isLinux
            && config.stylix.enable
            && config.stylix.targets.gtk.enable
            && config.stylix.targets.gtk.colors.enable
          )
          {
            # Keep this palette choice independent of the upstream Flatpak repair.
            # Solarized Light's text reaches 4.99:1 on base00 versus 4.39:1 on base01.
            stylix.targets.gtk.extraCss = lib.mkIf (polarity == "light") (
              lib.mkBefore ''
                @define-color dialog_bg_color #${config.lib.stylix.colors.base00};
              ''
            );
            # GTK 3 needs its own variant preference alongside the desktop color
            # scheme. Let GTK select the configured theme's variant, and allow
            # explicit user preferences to override this palette-derived default.
            gtk.gtk3.extraConfig.gtk-application-prefer-dark-theme = lib.mkDefault (polarity == "dark");
          };
    };
}
