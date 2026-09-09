let
  catalog = import ./packages.nix { };
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
      pkgs,
      self,
      system,
      ...
    }:
    {
      imports = [ ./options.nix ];
      fonts.fontconfig.enable = true;
      fonts.packages = selected {
        inherit
          config
          pkgs
          self
          system
          ;
      };
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
      pkgs,
      self,
      system,
      ...
    }:
    {
      imports = [ ./options.nix ];
      fonts.fontconfig.enable = lib.mkDefault true;
      # HM builds the Linux profile cache and copies Darwin fonts natively.
      home.packages = selected {
        inherit
          config
          pkgs
          self
          system
          ;
      };
    };
}
