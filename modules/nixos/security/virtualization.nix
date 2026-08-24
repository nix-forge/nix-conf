{ config, lib, ... }: {
  security.virtualisation = {
    # NixOS implements this option with the Intel-only
    # `kvm-intel.vmentry_l1d_flush` parameter.  Leaving it at the kernel
    # default is therefore the only portable shared policy; an Intel host that
    # runs untrusted guests must make and document its own mitigation choice.
    flushL1DataCache = lib.mkDefault null;
  };

  assertions = [
    {
      # L1D flushing does not fully isolate a malicious guest from sibling
      # hyperthreads.  Do not claim the strongest mode without also removing
      # SMT; both choices are deliberately expensive and host-specific.
      assertion =
        config.security.virtualisation.flushL1DataCache != "always"
        || !config.security.allowSimultaneousMultithreading;
      message = "security.virtualisation.flushL1DataCache = \"always\" is an untrusted-guest mitigation and must be paired with security.allowSimultaneousMultithreading = false on the affected Intel host.";
    }
  ];

  # Do not enable a hypervisor, libvirt, VFIO, a virtual bridge, or a device
  # ACL here.  Those settings define which guests and users can control real
  # hardware and networking, and belong in a host's local/ configuration.
}
