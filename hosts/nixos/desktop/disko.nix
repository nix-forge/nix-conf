{
  lib,
  systemDisk ? "/dev/disk/by-id/UNCONFIGURED-SYSTEM",
  dataDisk ? "/dev/disk/by-id/UNCONFIGURED-DATA",
  ...
}:
let
  # Installed mounts use partition labels and mapper names. Physical disk IDs
  # are supplied only to the offline installer, never required for a rebuild.
  # These deliberately nonexistent defaults cannot select a physical drive.
  checkedDisk =
    disk:
    if lib.hasPrefix "/dev/disk/by-id/" disk && !lib.hasInfix "/../" disk then
      disk
    else
      throw "Disko requires an explicitly verified /dev/disk/by-id path.";
  btrfsOptions = [
    "compress=zstd:1"
    "noatime"
    "nodiscard"
  ];
  optionalOptions = btrfsOptions ++ [
    "nofail"
    "x-systemd.device-timeout=10s"
  ];
  subvolume = mountpoint: {
    inherit mountpoint;
    mountOptions = btrfsOptions;
  };
  dataSubvolume = mountpoint: {
    inherit mountpoint;
    mountOptions = optionalOptions;
  };
  btrfs = label: subvolumes: {
    type = "btrfs";
    extraArgs = [
      "-f"
      "-L"
      label
      "-d"
      "single"
      "-m"
      "dup"
    ];
    inherit subvolumes;
  };
  luks = name: content: {
    type = "luks";
    inherit name content;
    extraFormatArgs = [
      "--type"
      "luks2"
      "--pbkdf"
      "argon2id"
    ];
    settings.allowDiscards = true;
  };
in
assert systemDisk != dataDisk;
{
  disko.devices.disk = {
    system = {
      type = "disk";
      device = checkedDisk systemDisk;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            priority = 1;
            label = "NIXOS-ESP";
            size = "2G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [
                "fmask=0077"
                "dmask=0077"
              ];
            };
          };
          swap = {
            priority = 2;
            label = "NIXOS-SWAP";
            size = "16G";
            type = "8200";
            content = {
              type = "swap";
              randomEncryption = true;
              priority = -1;
              mountOptions = [ "nofail" ];
            };
          };
          cryptroot = {
            label = "NIXOS-CRYPTROOT";
            size = "100%";
            content = luks "cryptroot" (
              btrfs "nixos" {
                "@root" = subvolume "/";
                "@home" = subvolume "/home";
                "@home/.snapshots" = { };
                "@nix" = subvolume "/nix";
                "@var" = subvolume "/var";
                "@log" = subvolume "/var/log";
                "@cache" = subvolume "/var/cache";
                "@docker" = subvolume "/var/lib/docker";
                "@containerd" = subvolume "/var/lib/containerd";
                # Nested subvolume avoids retaining rootless Docker layers in
                # every home snapshot. Ownership is established after mounting.
                "@docker-rootless" = subvolume "/home/ianmh/.local/share/docker";
              }
            );
          };
        };
      };
    };
    data = {
      type = "disk";
      device = checkedDisk dataDisk;
      content = {
        type = "gpt";
        partitions.cryptdata = {
          label = "NIXOS-CRYPTDATA";
          size = "100%";
          content =
            (luks "cryptdata" (
              btrfs "desktop-data" {
                "@data" = dataSubvolume "/srv/data";
                "@data/.snapshots" = { };
                "@work" = dataSubvolume "/srv/data/work";
                "@work/.snapshots" = { };
                "@games" = dataSubvolume "/mnt/games";
                "@vms" = dataSubvolume "/var/lib/libvirt/images";
              }
            ))
            // {
              # Its key lives on encrypted root. Never copy it into the initrd.
              initrdUnlock = false;
            };
        };
      };
    };
  };
}
