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
    # Do not enable libvirt or bind PCI devices to VFIO until the Windows VM
    # design selects its GPU, audio function, USB controller, storage image,
    # network exposure, recovery path, and host-display fallback.  This host's
    # AMD IOMMU is already active, but FireWire capture currently logs IOMMU
    # faults, so changing IOMMU mode is out of scope for this baseline.
    libvirtd.enable = false;
  };

  # Rootless Docker can enforce CPU, cpuset, I/O, memory, and PID limits only
  # when the user manager receives those cgroup-v2 controllers. This is a
  # host-wide resource-policy decision, so it belongs in this local module.
  systemd.services."user@".serviceConfig.Delegate = "cpu cpuset io memory pids";
}
