{ nixosHyprland, ... }: { pkgs, lib, ... }: {
  xdg.portal = lib.mkIf (!nixosHyprland) {
    # Home Manager's Hyprland module supplies the matching Hyprland portal and
    # its upstream portal configuration.  Add only GTK here for interfaces the
    # compositor backend does not implement; duplicating the Hyprland package
    # would create competing portal definitions in a standalone profile.
    xdgOpenUsePortal = true;

    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

    config = {
      hyprland.default = [
        "hyprland"
        "gtk"
      ];
    };
  };
}
