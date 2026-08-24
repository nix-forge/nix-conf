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
  systemd.services.telegraf.path = lib.mkAfter [ pkgs.nvme-cli ];
}
