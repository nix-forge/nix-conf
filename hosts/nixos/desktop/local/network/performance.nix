{
  networking.performanceTuning = {
    enable = true;

    # The wired NIC uses fq_codel, but changing congestion control without a
    # measured workload gain is unnecessary. Keep the kernel's CUBIC default.
    congestionControl = "cubic";

    # VPNs and filtered networks can lose Path-MTU ICMP messages. Enable only
    # black-hole recovery, not unconditional probing.
    enableMtuBlackholeRecovery = true;
    enableSynCookies = true;
  };
}
