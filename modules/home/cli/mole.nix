{ lib, pkgs, ... }:
lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
  # Mole cleans macOS application leftovers and is intentionally unavailable
  # on Linux. Keep the aggregate `cli` module portable across both platforms.
  home.packages = [ pkgs.mole-cleaner ];
}
