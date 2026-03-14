{
  self,
  system,
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isAarch64;
in
{
  home.packages = lib.mkIf (isDarwin && isAarch64) [ self.packages.${system}.codex-app ];
}
