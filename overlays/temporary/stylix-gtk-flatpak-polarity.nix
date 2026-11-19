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
      # The generated module no longer shares the upstream relative directory.
      template = builtins.toFile "stylix-gtk.css.mustache" (
        builtins.readFile (stylix + "/modules/gtk/gtk.css.mustache")
      );
      old = [
        "  options,\n"
        "cat \${finalCss} | tee --append $out/gtk-{3,4}.0/gtk.css"
        "theme = config.gtk.theme.name;"
        "template = ./gtk.css.mustache;"
      ];
      replacement = [
        "  options,\n  gtkPolarity,\n"
        ((''
          # shellcheck shell=bash
          # Nix builder/activation callers and rendered fragments provide external variables.
          # shellcheck disable=SC2154
          for stylesheet in "$out"/gtk-{3,4}.0/gtk.css "$out"/gtk-{3,4}.0/gtk-dark.css "$out"/gtk-{3,4}.0/gtk-light.css; do
            if [ -f "$stylesheet" ]; then
              cat "''${finalCss}" >>"$stylesheet"
            fi
          done
        ''))
        ''
          preferDark = config.gtk.gtk3.extraConfig.gtk-application-prefer-dark-theme
            or (gtkPolarity == "dark");
          theme = "''${config.gtk.theme.name}:''${if preferDark then "dark" else "light"}";
        ''
        "template = ${template};"
      ];
      patchedTarget = builtins.toFile "stylix-gtk-flatpak-polarity.nix" (
        if !(builtins.all (text: lib.hasInfix text source) old) then
          throw "Stylix GTK Flatpak source changed; review the polarity repair"
        else
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
          in
          (import patchedTarget) {
            inherit
              config
              gtkPolarity
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
