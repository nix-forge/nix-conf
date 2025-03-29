{
  config,
  inputs,
  pkgs,
  ...
}:
{
  programs.hyprland = {
    enable = true;
    # set the flake package
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    # make sure to also set the portal package, so that they are in sync
    portalPackage =
      inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;

    # Use UWSM as the display manager
    withUWSM = true;
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;

    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];

    config = {
      common.default = [ "gtk" ];
      hyprland.default = [
        "hyprland"
        "gtk"
      ];
    };

  };

  security.pam.services.hyprlock = { };

  hardware.graphics =
    let
      nixpkgs-hyprland = inputs.hyprland.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
    in
    {
      enable = true;
      extraPackages = [ nixpkgs-hyprland.mesa ];

      enable32Bit = true;
      extraPackages32 = [ nixpkgs-hyprland.pkgsi686Linux.mesa ];
    };

  environment.systemPackages = with pkgs; [
    kdePackages.xwaylandvideobridge
    grim
    slurp
  ];

  programs.xwayland.enable = true;
}
