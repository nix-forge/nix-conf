{ pkgs, ... }:
let
  direnvPkg = pkgs.direnv.overrideAttrs {
    postPatch = ''
      substituteInPlace GNUmakefile --replace-fail " -linkmode=external" ""
    '';
  };
in
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    package = direnvPkg;
  };
}
