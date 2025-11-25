{
  dockerAlias ? false,
}:
# TODO: update config once darwin podman module is added to home manager
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

  darwin =
    lib.mkIf pkgs.stdenv.hostPlatform.isDarwin { home.packages = [ pkgs.podman ]; }
    // lib.optionalAttrs dockerAlias {
      xdg.configFile."containers/registries.conf".text = ''
        unqualified-search-registries = ["docker.io"]

        short-name-mode = "permissive"
      '';

      xdg.configFile."containers/containers.conf".text = ''
        [engine]
        image_default_transport = "docker://"

        compat_api_enforce_docker_hub = true
      '';

      home.shellAliases = {
        docker = "podman";
        docker-compose = "podman-compose";
      };
    };
in
lib.mkMerge [
  all
  darwin
  linux
]
