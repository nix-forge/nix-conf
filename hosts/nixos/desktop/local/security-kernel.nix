{
  security.kernelBaseline.enable = true;

  security = {
    # Rootless Docker, modern browser sandboxes, and several desktop tools
    # require user namespaces. They remain enabled, while unprivileged BPF is
    # independently disabled by the shared kernel baseline.
    allowUserNamespaces = true;

    # This Ryzen 7 7700X reports Meltdown as not affected. Keep the kernel's
    # normal PTI decision instead of paying a forced-PTI cost without a proven
    # benefit for this CPU. Revisit this if the desktop starts running
    # untrusted workloads with a materially different threat model.
    forcePageTableIsolation = false;

    # Keep all 16 logical CPUs for gaming, compilation, and media work. SMT
    # disablement is an expensive, host-specific mitigation for untrusted VM
    # guests; this workstation does not currently run such guests.
    allowSimultaneousMultithreading = true;
  };

  # These loadable protocols are available in the running kernel but have no
  # role on this workstation. Blacklisting is intentionally narrow: do not
  # blacklist FireWire (MiniDV capture), Bluetooth, USB storage, FUSE,
  # SquashFS, or Thunderbolt/USB4 pre-emptively, because those are either in
  # use or need a separately reviewed hardware policy.
  boot.blacklistedKernelModules = [
    "appletalk"
    "atm"
    "n-hdlc"
    "rds"
    "sctp"
    "tipc"
    "x25"
  ];
}
