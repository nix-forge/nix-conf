{
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv) isLinux;
in
{
  xdg = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    userDirs = {
      enable = true;
      createDirectories = true;
    };
  };
}
