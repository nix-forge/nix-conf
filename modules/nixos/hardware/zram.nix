{ config, lib, ... }: {
  # zram holds compressed swapped pages in RAM, avoiding slow storage I/O until
  # memory pressure exceeds what compression can absorb.  These are reusable
  # defaults: host-specific capacity and memory ceilings belong in local/.
  zramSwap = {
    enable = lib.mkDefault true;
    # zstd favours compression ratio, which is useful for general desktop
    # workloads and is supported by current kernels.
    algorithm = lib.mkDefault "zstd";
    # Use one device: NixOS and zram-generator recommend this normal case.
    swapDevices = lib.mkDefault 1;
    # Prefer zram to any physical swap device, whose priority should remain
    # lower.  This is an ordering preference, not a memory reservation.
    priority = lib.mkDefault 5;
    # Logical zram capacity.  It does not preallocate RAM; local hosts may set
    # a resident-memory limit through services.zram-generator instead.
    memoryPercent = lib.mkDefault 50;
  };

  # Retain systemd-oomd as a last-resort, pressure-aware safety net.  Do not
  # opt whole root, system, or user slices into eviction here: that policy is
  # workload-specific and can otherwise kill an entire desktop session.
  systemd.oomd.enable = lib.mkDefault true;

  assertions = [
    {
      # Both layers compress swap in RAM.  NixOS treats their combination as
      # unsupported, and it wastes CPU while making pressure behavior opaque.
      assertion = !(config.zramSwap.enable && config.boot.zswap.enable);
      message = "zramSwap and boot.zswap must not be enabled together; choose one compressed-swap layer.";
    }
  ];

  # Do not set zram writebackDevice generically.  It needs a dedicated,
  # deliberately provisioned backing block device and a wear/latency policy;
  # reusing an existing swap partition for writeback is unsafe.
}
