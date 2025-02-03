{ pkgs, inputs, ... }:
{
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;

    extraPortals = [
      # pkgs.xdg-desktop-portal-hyprland
      inputs.xdph.packages.${pkgs.system}.default

      # pkgs.xdg-desktop-portal
      # pkgs.xdg-desktop-portal-kde
      pkgs.xdg-desktop-portal-gtk
    ];

    config = {
      common.default = [ "gtk" ];
      hyprland.default = [
        "hyprland"
        "kde"
        "gtk"
      ];
    };
  };
}
