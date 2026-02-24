{ pkgs, lib, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
in
{
  home.packages = [ pkgs.podman-compose ] ++ lib.optionals isDarwin [ pkgs.container ];

  services.podman = {
    enable = true;
    enableTypeChecks = isLinux;
  }
  // lib.optionalAttrs isDarwin {
    machines.podman-machine-default = {
      autoStart = false;
      memory = 4 * 1024;
    };
  };

  home.shellAliases = {
    docker = "podman";
    docker-compose = "podman-compose";
  };
}
