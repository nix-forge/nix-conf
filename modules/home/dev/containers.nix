{ pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
in
{
  home.packages =
    if isDarwin then
      [ pkgs.container ]
    else
      with pkgs;
      [
        docker
        docker-compose
        docker-buildx
      ];
}
