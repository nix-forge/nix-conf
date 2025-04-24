{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  pkgsNur = (import inputs.nixpkgs {
    inherit (pkgs) system;
    overlays = [ inputs.nur.overlays.default ];
  }).nur;
in
{
  programs.ghostty = {
    enable = true;
    package = lib.mkIf (pkgs.stdenv.isDarwin) pkgsNur.repos.DimitarNestorov.ghostty;
  };
}
