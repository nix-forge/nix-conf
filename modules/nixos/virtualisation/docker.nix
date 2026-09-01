{ lib, ... }: {
  # Run Docker only through the unprivileged per-user daemon. Keeping the
  # rootful daemon off removes its root-equivalent socket and system service.
  # The host's local policy selects the eligible account.
  virtualisation.docker = {
    enable = false;

    rootless = {
      enable = true;

      # The Home Manager Docker context selects the rootless socket. Do not
      # globally override a deliberate per-shell DOCKER_HOST selection.
      setSocketVariable = false;

      daemon.settings = {
        # BuildKit is Docker's supported build backend and provides parallel
        # builds, cache mounts, secrets, and SSH mounts.
        features.buildkit = true;

        # Keep logs local to Docker and bounded. This avoids an unbounded
        # journal or json-file log while retaining `docker logs` UX.
        "log-driver" = "local";
        "log-opts" = {
          "max-file" = "3";
          "max-size" = "10m";
        };

        # Private cgroup namespaces reduce what a container can infer about
        # the host. Rootless Docker already gives containers a user namespace.
        "default-cgroupns-mode" = "private";

        # New bridge networks bind published ports to loopback unless the
        # workload explicitly selects another address.
        "default-network-opts".bridge."com.docker.network.bridge.host_binding_ipv4" = "127.0.0.1";

        # Containers cannot acquire additional privileges through setuid,
        # setgid, or file capabilities unless a workload opts out explicitly.
        "no-new-privileges" = true;

        # Keep development containers alive across a deliberate daemon reload.
        # `docker-down` stops containers explicitly when their resources are no
        # longer needed.
        "live-restore" = true;
      };
    };
  };

  # The upstream rootless NixOS unit is enabled at every user login and
  # restarts unconditionally. Keep it disabled until `docker-up` starts it;
  # a clean stop stays stopped and costs no daemon CPU or memory.
  systemd.user.services.docker = {
    wantedBy = lib.mkForce [ ];
    serviceConfig.Restart = lib.mkForce "on-failure";
  };
}
