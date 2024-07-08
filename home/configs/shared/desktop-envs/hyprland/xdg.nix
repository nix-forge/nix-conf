{
  inputs,
  pkgs,
  config,
  ...
}:
{
  xdg.portal =
    let
      portalPackages = [
        pkgs.xdg-desktop-portal-gtk
        inputs.hyprland.packages.${pkgs.system}.xdg-desktop-portal-hyprland
      ];
    in
    {
      enable = true;
      configPackages = portalPackages;
      extraPortals = portalPackages;
      # Based On: https://wiki.hyprland.org/Useful-Utilities/Hyprland-desktop-portal/
      config = {
        preffered = {
          default = [
            "hyprland"
            "gtk"
          ];
          "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
        };
      };
    };
}
