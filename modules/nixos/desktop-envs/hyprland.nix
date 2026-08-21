{ config, pkgs, ... }: {
  programs.hyprland = {
    enable = true;
    # Keep the compositor and portal on the same nixpkgs revision as the
    # kernel, NVIDIA driver, and wlroots stack.  The former flake-input
    # reference was not declared by this repository and therefore made the
    # module unevaluable when enabled.
    package = pkgs.hyprland;
    portalPackage = pkgs.xdg-desktop-portal-hyprland;

    withUWSM = true;
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
}
