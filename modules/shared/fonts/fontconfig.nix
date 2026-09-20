# Feature-local Fontconfig rendering helper. This file intentionally exports
# data rather than a NixOS/Home Manager module envelope, so the shared-module
# selector ignores it while the fonts feature can reuse one renderer.
{
  render =
    {
      pkgs,
      fonts,
      myLib,
      fontPackages ? [ ],
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
      privateUseFamilyAliases = myLib.writers.writeBashTemplate { inherit pkgs; } {
        name = "fontconfig-private-use-family-aliases";
        src = ./private-use-family-aliases.sh.in;
        dir = "bin";
        replacements = {
          fontDirectories = lib.concatMapStringsSep " " lib.escapeShellArg fontDirectories;
          privateUseFallbackFamily = lib.escapeShellArg compatibility.privateUseFallbackFamily;
          appleSystemFamily = lib.escapeShellArg compatibility.appleSystemFamily;
          blinkMacSystemFamily = lib.escapeShellArg compatibility.blinkMacSystemFamily;
          appleColorEmojiFamily = lib.escapeShellArg compatibility.appleColorEmojiFamily;
          appleSansPrefix = lib.escapeShellArg compatibility.appleSansPrefix;
          appleSerifPrefix = lib.escapeShellArg compatibility.appleSerifPrefix;
          appleHelveticaNeueFamily = lib.escapeShellArg compatibility.appleHelveticaNeueFamily;
        };
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.fontconfig
          pkgs.gnused
        ];
        inheritPath = false;
      };
      generatedPrivateUseFamilyAliases = pkgs.runCommand "fontconfig-private-use-family-aliases" { } ''
        mkdir -p "$out"
        ${privateUseFamilyAliases}/bin/fontconfig-private-use-family-aliases "$out/aliases.conf"
      '';
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
      package = pkgs.runCommand "fontconfig-shared-rules" { } ''
        install -d "$out/etc/fonts/conf.d"
        ln -s ${rendered.cssGenericAlias} "$out/etc/fonts/conf.d/51-shared-css-generic-alias.conf"
        ln -s ${rendered.privateUseFallback} "$out/etc/fonts/conf.d/51-shared-private-use-fallback.conf"
      '';
    };
}
