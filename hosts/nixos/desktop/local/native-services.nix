{ config, lib, ... }: {
  # Fail evaluation if an imported service tries to reintroduce a runtime.
  virtualisation.docker.enable = false;
  virtualisation.docker.rootless.enable = false;
  virtualisation.podman.enable = false;
  virtualisation.containerd.enable = false;
  virtualisation.oci-containers.containers = { };
  assertions = [
    {
      assertion =
        !config.virtualisation.docker.enable
        && !config.virtualisation.docker.rootless.enable
        && !config.virtualisation.podman.enable
        && !config.virtualisation.containerd.enable
        && config.virtualisation.oci-containers.containers == { }
        && config.containers == { }
        && !config.services.flatpak.enable;
      message = "Desktop applications must use native Nix packages and systemd services, without container runtimes.";
    }
    {
      assertion = lib.all (home: !home.programs.docker-cli.enable) (
        builtins.attrValues config.home-manager.users
      );
      message = "Desktop home profiles must not enable Docker tooling.";
    }
  ];
}
