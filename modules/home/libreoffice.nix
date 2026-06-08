{
  lib,
  pkgs,
  self,
  system,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;

  libreofficePackage =
    if isDarwin then self.packages.${system}.libreoffice else pkgs.libreoffice-fresh;
in
{
  home.packages = [
    libreofficePackage
    pkgs.languagetool
  ]
  ++ lib.optionals isLinux [ pkgs.hunspellDicts.en_US-large ];
}
