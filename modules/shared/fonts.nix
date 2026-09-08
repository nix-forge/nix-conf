let
  catalog = import ./font-packages.nix { };
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
      imports = [
        ./font-options.nix
        ../nixos/locale/font-selection.nix
      ];
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
      imports = [ ./font-options.nix ];
      fonts.fontconfig.enable = lib.mkDefault true;
      fonts.fontconfig.configFile.current-emoji = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        enable = true;
        priority = 60;
        text = ''
          <?xml version="1.0"?>
          <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
          <fontconfig>${builtins.readFile ./font-selection.conf}</fontconfig>
        '';
      };
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
