{ config, pkgs, ... }:
let
  enable = pkgs.writeShellScript "desktop-enable-iocost" ''
    set -euo pipefail
    device="''${1-}"
    if [[ ! "$device" =~ ^[0-9]+:[0-9]+$ ]]; then
      echo 'Expected a whole-disk major:minor device number' >&2
      exit 2
    fi
    # Let the kernel adapt its cost model and saturation thresholds. Fixed
    # throughput/latency coefficients require measurements of each drive.
    printf '%s ctrl=auto\n' "$device" > /sys/fs/cgroup/io.cost.model
    printf '%s enable=1 ctrl=auto\n' "$device" > /sys/fs/cgroup/io.cost.qos
  '';
in
{
  # IOWeight needs an active proportional controller. These NVMe drives use
  # the none scheduler and have no hwdb iocost profile. Retain that scheduler
  # and enable the kernel's adaptive model rather than inventing fixed limits.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", KERNEL=="nvme[0-9]*n[0-9]*", ENV{IOCOST_SOLUTIONS}=="", RUN+="${enable} %M:%m"
  '';

  # Apply to already present devices on activation as well as cold-plug. A
  # model-specific hwdb profile, when available, remains owned by systemd.
  systemd.services.desktop-iocost = {
    description = "Enable adaptive I/O sharing on desktop NVMe drives";
    wantedBy = [ "multi-user.target" ];
    after = [
      "local-fs.target"
      "systemd-udev-trigger.service"
    ];
    before = [ "nix-daemon.service" ];
    path = [
      pkgs.coreutils
      config.systemd.package
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      shopt -s nullglob
      for device in /sys/block/nvme*n*; do
        properties=$(udevadm info --query=property --path="$device")
        if [[ "$properties" == *IOCOST_SOLUTIONS=* ]]; then
          continue
        fi
        ${enable} "$(cat "$device/dev")"
      done
    '';
  };

  # Top-level siblings compete before their descendants do. Give the user
  # subtree preference over background system services under contention.
  systemd.slices.user.sliceConfig.IOWeight = 200;

  system.build.desktopIOCostPolicy = pkgs.linkFarm "desktop-iocost-policy" [
    {
      name = "enable";
      path = enable;
    }
    {
      name = "desktop-iocost.service";
      path = "${config.systemd.units."desktop-iocost.service".unit}/desktop-iocost.service";
    }
    {
      name = "udev.rules";
      path = pkgs.writeText "desktop-udev.rules" config.services.udev.extraRules;
    }
  ];
}
