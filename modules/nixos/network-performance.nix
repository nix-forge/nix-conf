{ config, lib, ... }:
let
  cfg = config.networking.performanceTuning;
  useBbr = cfg.congestionControl == "bbr";
in
{
  options.networking.performanceTuning = {
    enable = lib.mkEnableOption "the network performance and resilience baseline";

    congestionControl = lib.mkOption {
      type = lib.types.enum [
        "cubic"
        "bbr"
      ];
      default = "cubic";
      description = ''
        TCP congestion-control algorithm for new connections. CUBIC remains
        the conservative generic default. Select BBR locally only after
        confirming the installed kernel provides tcp_bbr and the host benefits
        from paced WAN transfers.
      '';
    };

    enableMtuBlackholeRecovery = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable Packetization-Layer Path MTU probing only after TCP detects an
        ICMP Path-MTU black hole. This preserves ordinary Path MTU Discovery
        while allowing affected TCP connections to recover.
      '';
    };

    enableSynCookies = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Retain TCP SYN-cookie protection for listening services under a SYN
        flood. This is a resilience control, not a substitute for sizing an
        application's listen backlog.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.optionals useBbr [
      {
        assertion = !lib.elem "tcp_bbr" config.boot.blacklistedKernelModules;
        message = "networking.performanceTuning selects BBR but tcp_bbr is blacklisted.";
      }
    ];

    # BBR is a kernel module with an explicit Fair Queue pacing requirement.
    # Load it before systemd-sysctl applies the congestion-control choice at
    # boot; NixOS orders systemd-sysctl after systemd-modules-load.
    boot.kernelModules = lib.optionals useBbr [ "tcp_bbr" ];

    boot.kernel.sysctl = {
      # 1 means PMTU probing remains off for normal paths and is activated only
      # when TCP detects an ICMP black hole. Never use value 2 as a blanket
      # workaround: it unnecessarily changes the initial MSS on every path.
      "net.ipv4.tcp_mtu_probing" = if cfg.enableMtuBlackholeRecovery then 1 else 0;

      # Preserve a low-cost flood-resilience guard for any locally listening
      # TCP service. It does not tune application accept throughput.
      "net.ipv4.tcp_syncookies" = if cfg.enableSynCookies then 1 else 0;
    }
    // lib.optionalAttrs useBbr {
      # Linux's BBR implementation requires the fq pacing packet scheduler.
      # Do not retain fq_codel here: it is a sound general default, but it does
      # not supply the pacing contract that BBR is designed to use.
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
    };

    # Intentionally not set here:
    # - rmem/wmem/netdev backlog: large values trade latency and memory for a
    #   measured high-packet-rate or UDP workload; TCP autotuning is enabled.
    # - RPS/XPS and IRQ affinity: this desktop's Wi-Fi NIC exposes one RX/TX
    #   queue, and irqbalance already owns interrupt placement. Forcing CPU
    #   masks would add IPIs or fight the active balancer.
    # - tcp_ecn, tcp_fastopen, keepalive, or idle slow-start policy: each is
    #   sensitive to middleboxes or application protocols and belongs in a
    #   measured, host- or service-specific change.
  };
}
