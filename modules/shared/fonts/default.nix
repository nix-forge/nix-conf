let
  catalog = import ./packages.nix { };
  renderFontconfig = (import ./fontconfig.nix).render;
  selected =
    {
      config,
      pkgs,
      self,
      system,
      ...
    }:
    let
      personal = self.packages.${system};
    in
    catalog.select pkgs personal config.typography;
in
{
  nixos =
    {
      config,
      lib,
      myLib,
      pkgs,
      self,
      system,
      ...
    }:
    let
      fontPackages = selected {
        inherit
          config
          pkgs
          self
          system
          ;
      };
      rendered = renderFontconfig {
        inherit myLib pkgs fontPackages;
        fonts = config.stylix.fonts;
      };
    in
    {
      imports = [ ./options.nix ];
      fonts.fontconfig.enable = true;
      fonts.fontconfig.confPackages = lib.mkAfter [ rendered.package ];
      fonts.packages = fontPackages;
    };
  darwin = { self, system, ... }: {
    # Native user fonts are owned by Home Manager. Only document fonts shared
    # across accounts are copied into /Library/Fonts/Nix Fonts.
    fonts.packages = catalog.appleDocumentFonts self.packages.${system};
  };
  homeManager =
    {
      config,
      lib,
      myLib,
      pkgs,
      self,
      system,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) isLinux;
      fontPackages = selected {
        inherit
          config
          pkgs
          self
          system
          ;
      };
    in
    {
      imports = [ ./options.nix ];
      # HM builds the Linux profile cache and copies Darwin fonts natively.
      home.packages = fontPackages;
      fonts.fontconfig = lib.mkIf isLinux (
        let
          rendered = renderFontconfig {
            inherit myLib pkgs fontPackages;
            fonts = config.stylix.fonts;
          };
        in
        {
          enable = lib.mkDefault true;
          configFile."css-generic-alias" = {
            enable = true;
            priority = 49;
            source = rendered.cssGenericAlias;
          };
          configFile."private-use-fallback" = {
            enable = true;
            priority = 50;
            source = rendered.privateUseFallback;
          };
        }
      );
    };
}
