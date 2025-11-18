{ pkgs, lib, ... }:
let
  all = {
    home.packages = [ pkgs.podman-compose ];
  };

  linux = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    services.podman = {
      enable = true;
      enableTypeChecks = true;

      autoUpdate.enable = true;
      autoUpdate.onCalendar = "Mon *-*-* 02:30";
    };
  };

  darwin = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin { home.packages = [ pkgs.podman ]; };
in
lib.mkMerge [
  all
  darwin
  linux
]
