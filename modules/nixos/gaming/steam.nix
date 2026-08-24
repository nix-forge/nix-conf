{ pkgs, ... }: {
  programs.steam = {
    enable = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];

    # Native NixOS support for common Proton repair workflows and Steam Input
    # from XWayland games under a Wayland desktop.
    protontricks.enable = true;
    extest.enable = true;

    # Adds an optional Steam Big Picture Gamescope session in the display
    # manager, without changing the normal GNOME desktop session.
    gamescopeSession = {
      enable = true;
    };
  };
}
