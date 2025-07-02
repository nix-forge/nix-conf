defaultbrowser:
{
  lib,
  pkgs,
  ...
}:
{
  home.activation = lib.mkIf pkgs.stdenv.isDarwin {
    setDefaultBrowser = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${lib.getExe pkgs.defaultbrowser} ${defaultbrowser}
    '';
  };
}
