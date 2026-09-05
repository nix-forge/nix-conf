{ inputs, pkgs, ... }:
let
  steamCefScaleOverride =
    inputs.nixpkgs-personal.packages.${pkgs.stdenv.hostPlatform.system}.steam-cef-scale-override;
in
{
  programs.steam = {
    enable = true;
    # Hyprland presents XWayland surfaces at native pixels on the 1.5x desktop
    # output. Force CEF to rasterize Steam's UI at the matching scale instead
    # of letting the compositor enlarge a 1x buffer. Preserve extest in the
    # combined preload because Steam Input under Wayland also depends on it.
    # The scale library itself is inert outside an executable named exactly
    # steamwebhelper, even if Steam forwards LD_PRELOAD to a launched game.
    package = pkgs.steam.override {
      extraEnv = {
        LD_PRELOAD = "${pkgs.pkgsi686Linux.extest}/lib/libextest.so:${steamCefScaleOverride}/lib/libsteam-cef-scale-override.so";
        STEAM_SCALE_FACTOR = "1.5";
      };
    };
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
