{
  self,
  system,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isAarch64;
in
{
  home.packages = lib.mkIf (isDarwin && isAarch64) [ self.packages.${system}.claude-desktop ];
}
