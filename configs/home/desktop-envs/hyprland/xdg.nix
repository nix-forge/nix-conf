{ pkgs, inputs, ... }:
{
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;

    extraPortals = [
      # pkgs.xdg-desktop-portal-hyprland
      inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland

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
}
