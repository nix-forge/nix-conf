{ lib, pkgs, ... }: {
  services.fstrim = {
    # `fstrim` skips filesystems and devices that do not implement discard, so a
    # periodic batch trim is a safe cross-host default.  It returns unused flash
    # blocks to SSD/NVMe firmware without adding write-time latency to foreground
    # workloads.  Hosts that use a storage stack with its own trim policy (for
    # example ZFS) can override this normally.
    enable = lib.mkDefault true;

    # The upstream NixOS default is weekly, which is an appropriate cadence for
    # both interactive systems and servers.  Keep it explicit so a change in the
    # upstream default is reviewed rather than silently changing maintenance.
    interval = lib.mkDefault "weekly";
  };

  # Batch maintenance should not compete with foreground work.  Whether the
  # machine must be on AC power is a host power-policy decision, so it belongs
  # in `local/`, not in this reusable SSD baseline.
  systemd.services.fstrim = {
    serviceConfig = {
      Nice = lib.mkDefault 19;
      IOSchedulingClass = lib.mkDefault "idle";

      # Keep online discard off and batch TRIM instead.  Skipping tiny extents
      # avoids the highest request overhead for the least reclaimed space.
      ExecStart = lib.mkForce [
        ""
        "${pkgs.util-linux}/bin/fstrim --all --minimum 1M"
      ];
    };
  };

  # Run missed maintenance after a machine was powered off at the scheduled
  # time, while avoiding synchronized I/O spikes across systems.
  systemd.timers.fstrim.timerConfig = {
    AccuracySec = lib.mkDefault "1h";
    Persistent = lib.mkDefault true;
    RandomizedDelaySec = lib.mkDefault "2h";
  };
}
