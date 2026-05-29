let
  stylixShared =
    { inputs, pkgs, ... }:
    {
      enable = true;
      autoEnable = true;

      # View various themes: https://tinted-theming.github.io/tinted-gallery/
      base16Scheme = inputs.stylix.inputs.tinted-schemes + "/base16/pop.yaml";
      polarity = "dark";

      opacity.terminal = 0.9;

      fonts = {
        monospace = {
          package = pkgs.nerd-fonts.monaspace;
          name = "MonaspiceNe Nerd Font";
        };

        sansSerif = {
          package = pkgs.inter;
          name = "Inter";
        };

        serif = {
          package = pkgs.google-fonts;
          name = "Literata";
        };

        emoji = {
          package = pkgs.noto-fonts-color-emoji;
          name = "Noto Color Emoji";
        };
      };
    };
  linuxShared =
    { pkgs, ... }:
    {
      cursor = {
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Classic";
        size = 20;
      };
      icons = {
        enable = true;
        package = pkgs.papirus-icon-theme;
        dark = "Papirus-Dark";
        light = "Papirus";
      };
    };
in
{
  nixos =
    {
      inputs,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [ inputs.stylix.nixosModules.default ];

      stylix = lib.mkMerge [
        (stylixShared { inherit inputs pkgs; })
        (linuxShared { inherit pkgs; })
        { homeManagerIntegration.autoImport = false; }
      ];
    };
  darwin =
    {
      inputs,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [ inputs.stylix.darwinModules.default ];

      stylix = lib.mkMerge [
        (stylixShared { inherit inputs pkgs; })
        { homeManagerIntegration.autoImport = false; }
      ];
    };
  homeManager =
    {
      inputs,
      pkgs,
      lib,
      osConfig ? null,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) isLinux;
      usesGlobalPkgs = osConfig != null && (osConfig.home-manager.useGlobalPkgs or false);
    in
    {
      imports = [ inputs.stylix.homeModules.default ];
      stylix = lib.mkMerge [
        (stylixShared { inherit inputs pkgs; })
        { overlays.enable = lib.mkForce (!usesGlobalPkgs); }
        (lib.mkIf isLinux (linuxShared {
          inherit pkgs;
        }))
      ];
    };
}
