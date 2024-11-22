{ inputs, pkgs, ... }:
{
  programs.hyprland = {
    enable = true;
    # set the flake package
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    # make sure to also set the portal package, so that they are in sync
    portalPackage =
      inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  };

  security.pam.services.hyprlock = { };

  hardware.graphics =
    let
      nixpkgs-hyprland = inputs.hyprland.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
    in
    {
      enable = true;
      extraPackages = [ nixpkgs-hyprland.mesa.drivers ];

      enable32Bit = true;
      extraPackages32 = [ nixpkgs-hyprland.pkgsi686Linux.mesa.drivers ];
    };

  environment.systemPackages = with pkgs; [ xwaylandvideobridge ];

  programs.xwayland.enable = true;
}
