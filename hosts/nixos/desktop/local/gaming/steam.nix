{ inputs, pkgs, ... }:
let
  steamCefScaleOverride =
    inputs.nixpkgs-personal.packages.${pkgs.stdenv.hostPlatform.system}.steam-cef-scale-override;
in
{
  # Hyprland presents XWayland surfaces at native pixels on this desktop's
  # 1.5x output. Rasterize Steam's UI at that scale. Preserve extest in the
  # preload because Steam Input under Wayland also depends on it.
  # The scale library is inert outside an executable named steamwebhelper.
  programs.steam.package = pkgs.steam.override {
    extraEnv = {
      LD_PRELOAD = "${pkgs.pkgsi686Linux.extest}/lib/libextest.so:${steamCefScaleOverride}/lib/libsteam-cef-scale-override.so";
      STEAM_SCALE_FACTOR = "1.5";
    };
  };
}
