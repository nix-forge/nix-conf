{ lib, ... }: {
  reason = "Stylix's Flatpak GTK_THEME bypasses GTK 3's variant preference and its flattened dark stylesheet lacks the generated palette.";
  upstream = "https://github.com/nix-community/stylix/blob/abff36bfab11cbdcd0723f41c1b0921e211be6ac/modules/gtk/hm.nix";
  removal = "Stylix's Flatpak theme selects the configured polarity and applies generated colors to both base and dark stylesheets.";
  reviewedRevision = "3e27b6c499e507df6e3bb8eca3614f5c95e28140";
  inputPath = [ "stylix" ];
  apply =
    stylix:
    let
      target = stylix + "/modules/gtk/hm.nix";
      source = builtins.readFile target;
      old = [
        "  options,\n"
        "./gtk.css.mustache"
        "cat \${finalCss} | tee --append $out/gtk-{3,4}.0/gtk.css"
        "theme = config.gtk.theme.name;"
      ];
      replacement = [
        "  options,\n  gtkTemplate,\n  gtkPolarity,\n"
        "gtkTemplate"
        (builtins.readFile ./scripts/append-gtk-polarity-css.sh)
        ''
          preferDark = config.gtk.gtk3.extraConfig.gtk-application-prefer-dark-theme
            or (gtkPolarity == "dark");
          theme = "''${config.gtk.theme.name}:''${if preferDark then "dark" else "light"}";
        ''
      ];
      patchedTarget = builtins.toFile "stylix-gtk-flatpak-polarity.nix" (
        assert lib.assertMsg (builtins.all (
          text: lib.hasInfix text source
        ) old) "Stylix GTK Flatpak source changed; review the polarity repair";
        builtins.replaceStrings old replacement source
      );
      mkTarget = import (stylix + "/stylix/mk-target.nix") {
        name = "gtk";
        humanName = "GTK";
      };
    in
    {
      disabledModules = [ target ];
      imports = [
        (
          {
            config,
            lib,
            pkgs,
            options,
            ...
          }:
          let
            gtkPolarity = (import ../../modules/shared/stylix/targets/gtk/resolve-polarity.nix).resolve {
              inherit lib;
              inherit (config.stylix) polarity;
              colors = config.lib.stylix.colors;
            };
            template = builtins.readFile (stylix + "/modules/gtk/gtk.css.mustache");
            # Solarized Light's text on base01 is 4.39:1. Base00 reaches 4.99:1.
            gtkTemplate =
              if gtkPolarity == "light" then
                builtins.replaceStrings
                  [ "@define-color dialog_bg_color #{{base01-hex}};" ]
                  [ "@define-color dialog_bg_color #{{base00-hex}};" ]
                  template
              else
                template;
          in
          (import patchedTarget) {
            inherit
              config
              gtkPolarity
              gtkTemplate
              lib
              pkgs
              options
              mkTarget
              ;
          }
        )
      ];
    };
}
