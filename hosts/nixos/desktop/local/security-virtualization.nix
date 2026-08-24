{
  security = {
    # Rootless Docker needs unprivileged user namespaces.  Keep that kernel
    # facility available for this workstation's container workload, while
    # retaining the rootless daemon instead of creating a root-equivalent
    # `docker` group or system socket.
    allowUserNamespaces = true;

    virtualisation.flushL1DataCache = null;
  };

  virtualisation = {
    # A rootless daemon is scoped to the desktop account by the ConditionUser
    # in local/system.nix.  Keep container logs bounded and compressed by
    # Docker's local driver, and preserve running development containers across
    # a daemon restart.  These are daemon-wide choices, so per-container
    # privileges, mounts, networks, and resource limits remain explicit in
    # each workload definition.
    docker.rootless.daemon.settings = {
      "live-restore" = true;
      "log-driver" = "local";
      "log-opts" = {
        "max-file" = "3";
        "max-size" = "10m";
      };
    };

    # Do not enable libvirt or bind PCI devices to VFIO until the Windows VM
    # design selects its GPU, audio function, USB controller, storage image,
    # network exposure, recovery path, and host-display fallback.  This host's
    # AMD IOMMU is already active, but FireWire capture currently logs IOMMU
    # faults, so changing IOMMU mode is out of scope for this baseline.
    libvirtd.enable = false;
  };
}
