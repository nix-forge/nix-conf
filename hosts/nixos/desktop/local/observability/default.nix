{ lib, pkgs, ... }: {
  # Export host health in Prometheus format for an SSH tunnel or a future
  # local/VPN-only Prometheus instance.  Do not expose metrics to the LAN: a
  # metrics endpoint reveals installed services, mounts, and hardware state.
  services.telegraf = {
    enable = true;

    extraConfig = {
      agent.interval = "60s";

      inputs = {
        cpu = {
          report_active = true;
          totalcpu = true;
        };
        disk.tagdrop = {
          fstype = [
            "tmpfs"
            "ramfs"
            "devtmpfs"
            "devfs"
            "iso9660"
            "overlay"
            "aufs"
            "squashfs"
            "efivarfs"
          ];
          device = [
            "rpc_pipefs"
            "lxcfs"
            "nsfs"
          ];
        };
        diskio = { };
        internal = { };
        kernel_vmstat = { };
        mem = { };
        smart.path_smartctl = "/run/wrappers/bin/smartctl-telegraf";
        swap = { };
        system = { };
        systemd_units = { };
      };

      outputs.prometheus_client = {
        listen = "127.0.0.1:9273";
        metric_version = 2;
      };
    };
  };

  # The SMART input needs read-only device access.  Grant it to the Telegraf
  # service through a narrowly scoped wrapper instead of running the exporter
  # as root.
  security.wrappers.smartctl-telegraf = {
    owner = "telegraf";
    group = "telegraf";
    capabilities = "cap_sys_admin,cap_dac_override,cap_sys_rawio+ep";
    source = "${pkgs.smartmontools}/bin/smartctl";
  };

  # NVMe tooling is needed by Telegraf's SMART collector on this physical host.
  systemd.services.telegraf = {
    path = lib.mkAfter [ pkgs.nvme-cli ];

    serviceConfig = {
      # The profile itself is defined in the desktop-local AppArmor policy
      # file and initially runs in complain mode.  Attaching by unit prevents
      # this metrics policy from affecting arbitrary Telegraf invocations.
      AppArmorProfile = "nixos-telegraf";

      # Telegraf's Prometheus listener is declaratively loopback-only.  Keep
      # the D-Bus and loopback socket families needed by systemd_units and the
      # exporter, while preventing raw, packet, and Netlink sockets.  Do not
      # use IPAddressDeny here: on this systemd release its BPF policy also
      # blocks the system D-Bus traffic required by systemd_units.
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];

      # The configured collectors only read host state.  Preserve their
      # required runtime access to /run, including the system D-Bus socket
      # used by systemd_units.  On this system, `ProtectSystem`,
      # `ProtectHome`, `PrivateTmp`, `ProtectControlGroups`, and the
      # `ProtectKernel*` mount views all deny that D-Bus write.  Keep those
      # disabled rather than silently losing host-health monitoring.
      ProtectClock = true;
      ProtectHostname = true;

      LockPersonality = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      UMask = "0077";

      # The SMART input launches a dedicated file-capability wrapper.  Keep
      # precisely the wrapper's four capabilities in the bounding set, and do
      # not give Telegraf an ambient network capability.  `NoNewPrivileges`
      # must remain false until SMART collection is split into a separate
      # helper: true would prevent that wrapper from acquiring its file caps.
      AmbientCapabilities = lib.mkForce "";
      CapabilityBoundingSet = [
        "CAP_DAC_OVERRIDE"
        "CAP_SETPCAP"
        "CAP_SYS_ADMIN"
        "CAP_SYS_RAWIO"
      ];
      NoNewPrivileges = false;
    };
  };
}
