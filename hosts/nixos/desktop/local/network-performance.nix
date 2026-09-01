{
  networking.performanceTuning = {
    enable = true;

    # This MediaTek Wi-Fi device reports a noqueue qdisc, so it cannot provide
    # the fq pacing queue BBR expects. Keep CUBIC and the driver's effective
    # fq_codel default rather than making BBR fall back to per-socket high-
    # resolution timers without a measured benefit. The shared module retains
    # its BBR path for a future paced Ethernet or multi-queue NIC.
    congestionControl = "cubic";

    # VPNs and filtered networks can lose Path-MTU ICMP messages. Enable only
    # black-hole recovery, not unconditional probing.
    enableMtuBlackholeRecovery = true;
    enableSynCookies = true;
  };
}
