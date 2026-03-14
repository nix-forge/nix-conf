{ pkgs, lib, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
in
{
  home.packages = lib.mkIf isDarwin [ pkgs.whatsapp-for-mac ];
}
