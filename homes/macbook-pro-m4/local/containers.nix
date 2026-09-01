_: {
  # Colima is personal MacBook policy. It is deliberately not a launchd
  # service: `docker-up` starts the VM and `docker-down` releases its RAM/CPU.
  services.colima = {
    enable = true;

    profiles.default = {
      isService = false;
      isActive = false;
      setDockerHost = false;

      settings = {
        runtime = "docker";
        arch = "host";
        vmType = "vz";
        mountType = "virtiofs";
        rosetta = true;

        # Start modestly. Increase only after a measured build or workload
        # needs it; an idle profile remains completely stopped.
        cpu = 2;
        memory = 4;
        disk = 60;

        kubernetes.enabled = false;
        forwardAgent = false;
        nestedVirtualization = false;
        network.address = false;
        portForwarder = "ssh";
      };
    };
  };
}
