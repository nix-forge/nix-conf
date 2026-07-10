{
  self,
  system,
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
in
{
  home.packages = lib.mkIf isDarwin [ self.packages.${system}.remindctl ];
}
