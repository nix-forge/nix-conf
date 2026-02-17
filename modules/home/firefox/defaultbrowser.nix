{ lib, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
in
{
  home.activation = lib.mkIf isDarwin {
    setDefaultBrowser = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${lib.getExe pkgs.defaultbrowser} "firefox";
    '';
  };

  home.sessionVariables.BROWSER = "firefox";
}
