_: {
  lib.homelabDiskLayout =
    {
      lib,
      homelabDisk ? "/dev/disk/by-id/usb-UNCONFIGURED-HOMELAB",
      ...
    }:
    let
      checkedDisk =
        if
          lib.hasPrefix "/dev/disk/by-id/usb-" homelabDisk
          && builtins.match "/dev/disk/by-id/usb-[^/]+" homelabDisk != null
          && builtins.match ".*-part[0-9]+" homelabDisk == null
        then
          homelabDisk
        else
          throw "The homelab Disko layout requires a verified whole-disk /dev/disk/by-id/usb- path.";
    in
    {
      # Provision this removable disk separately from the internal SSD layout.
      disko.devices.disk.homelab = {
        type = "disk";
        device = checkedDisk;
        content = {
          type = "gpt";
          partitions.crypt = {
            label = "HOMELAB-CRYPT";
            type = "8309";
            size = "100%";
            content = {
              type = "luks";
              name = "homelab";
              initrdUnlock = false;
              extraFormatArgs = [
                "--type"
                "luks2"
                "--pbkdf"
                "argon2id"
              ];
              content = {
                type = "btrfs";
                extraArgs = [
                  "-f"
                  "-L"
                  "homelab"
                  "-d"
                  "single"
                  "-m"
                  "dup"
                  "--csum"
                  "xxhash"
                ];
                subvolumes = {
                  "@homelab" = {
                    mountpoint = "/mnt/homelab";
                    mountOptions = [
                      "compress=zstd:1"
                      "noatime"
                      "nodiscard"
                      "nodev"
                      "nosuid"
                      "noexec"
                      "nofail"
                      "noauto"
                      "x-systemd.automount"
                      "x-systemd.device-timeout=10s"
                    ];
                  };
                  "@homelab/media" = { };
                  "@homelab/backups" = { };
                };
                postCreateHook = ''
                  (
                    top=$(mktemp -d)
                    mount "$device" "$top" -o subvolid=5
                    trap 'umount "$top"; rmdir "$top"' EXIT
                    chmod 0700 "$top/@homelab/backups"
                  )
                '';
              };
            };
          };
        };
      };
    };
}
