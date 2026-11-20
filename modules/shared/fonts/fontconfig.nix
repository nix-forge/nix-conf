# Feature-local Fontconfig rendering helper. This file intentionally exports
# data rather than a NixOS/Home Manager module envelope, so the shared-module
# selector ignores it while the fonts feature can reuse one renderer.
{
  render =
    {
      myLib,
      pkgs,
      fonts,
      fontPackages ? [ ],
      ...
    }:
    let
      inherit (pkgs) lib;
      catalog = import ./packages.nix { };
      inherit (catalog) compatibility;
      xml = lib.escapeXML;
      fontDirectories = map (fontPackage: "${fontPackage}/share/fonts") fontPackages;
      roleReplacements = {
        sansSerifFamily = xml fonts.sansSerif.name;
        serifFamily = xml fonts.serif.name;
        monospaceFamily = xml fonts.monospace.name;
      };
      aliasTools = (import ../../../flake/runtime-packages.nix { inherit pkgs; }).fontconfigAliasTools;
      aliasPolicy = pkgs.writeText "fontconfig-alias-policy.json" (
        builtins.toJSON (compatibility // { inherit fontDirectories; })
      );
      privateUseFamilyAliases = myLib.writers.writeShellApplication { inherit pkgs; } {
        name = "fontconfig-private-use-family-aliases";
        runtimeInputs = [ pkgs.fontconfig ];
        inheritPath = false;
        text = ''
          exec ${lib.getExe aliasTools} ${aliasPolicy} "$@"
        '';
      };
      generatedPrivateUseFamilyAliases = pkgs.runCommand "fontconfig-private-use-family-aliases" { } (
        myLib.templates.renderText {
          name = "generate-private-use-family-aliases.sh";
          text = ''
            # shellcheck shell=bash
            # Nix builder/activation callers and rendered fragments provide external variables.
            # shellcheck disable=SC2154
            mkdir -p "$out"
            @privateUseFamilyAliases@/bin/fontconfig-private-use-family-aliases "$out/aliases.conf"
          '';
        } { inherit privateUseFamilyAliases; }
      );
      privateUseFallbackReplacements = {
        appleColorEmojiFamily = xml compatibility.appleColorEmojiFamily;
        privateUseFallbackFamily = xml compatibility.privateUseFallbackFamily;
        privateUseFamilyAliases = "${generatedPrivateUseFamilyAliases}/aliases.conf";
      };
      renderTemplate =
        name: src: replacements:
        pkgs.replaceVarsWith {
          inherit name src;
          inherit replacements;
        };
      rendered = {
        cssGenericAlias =
          renderTemplate "css-generic-alias.conf" ./css-generic-alias.conf.in
            roleReplacements;
        privateUseFallback =
          renderTemplate "private-use-fallback.conf" ./private-use-fallback.conf.in
            privateUseFallbackReplacements;
      };
    in
    rendered
    // {
      package = pkgs.linkFarm "fontconfig-shared-rules" [
        {
          name = "etc/fonts/conf.d/51-shared-css-generic-alias.conf";
          path = rendered.cssGenericAlias;
        }
        {
          name = "etc/fonts/conf.d/51-shared-private-use-fallback.conf";
          path = rendered.privateUseFallback;
        }
      ];
    };
}
