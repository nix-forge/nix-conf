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

    # Set to UWSM to false as we are manually setting it
     withUWSM = false;
  };

  # Configure UWSM to launch Hyprland from a display manager like SDDM
  programs.uwsm = {
    enable = true;
    waylandCompositors = {
      hyprland = {
        prettyName = "Hyprland";
        comment = "Hyprland compositor managed by UWSM";
        binPath = "/run/current-system/sw/bin/Hyprland";
      };
    };
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;

    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      config.programs.hyprland.portalPackage
    ];

    config.hyprland.default = [
      "hyprland"
      "gtk"
    ];
  };

  security.pam.services.hyprlock = { };

  # hardware.graphics =
  #   let
  #     nixpkgs-hyprland = inputs.hyprland.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  #   in
  #   {
  #     enable = true;
  #     extraPackages = [ nixpkgs-hyprland.mesa ];

  #     enable32Bit = true;
  #     extraPackages32 = [ nixpkgs-hyprland.pkgsi686Linux.mesa ];
  #   };

  environment.systemPackages = with pkgs; [
    kdePackages.xwaylandvideobridge
    grim
    slurp
  ];
}
