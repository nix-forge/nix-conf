{ lib, ... }:
let
  # This identity was read from the desktop itself. It identifies the ADATA
  # Linux system SSD by model and serial rather than mutable nvme0/nvme1 names.
  # It is deliberately host-local: do not reuse this file for another machine.
  systemDisk = "/dev/disk/by-id/nvme-ADATA_SX8200PNP_2N1429QJEQR7";

  btrfsMountOptions = [
    # zstd:1 is a balanced desktop setting: modest CPU use, good metadata and
    # text compression, and Btrfs skips incompressible game/archive data.
    "compress=zstd:1"
    "noatime"
    # Btrfs otherwise defaults to asynchronous discard on supported devices.
    # Determinate Nixd can delete many store paths at once, so batch TRIM is
    # preferable to issuing discards while its collector is active.
    "nodiscard"
  ];
in
{
  # This is an installer-only declaration. It must be imported together with
  # inputs.disko.nixosModules.disko only after booting a recovery installer.
  # Disko's destroy/format mode erases *all* partitions on systemDisk.
  #
  # The current ESP on this SSD is also the registered Windows Boot Manager
  # location. Preserve or relocate that boot path before using this layout;
  # Disko intentionally does not support preserving a Windows dual boot here.
  disko.devices.disk.system = {
    type = "disk";
    device = systemDisk;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          # Lanzaboote's signed boot generations, systemd-boot, and firmware
          # capsules all live on the ESP. 2 GiB leaves room for eight signed
          # generations and recovery headroom without another unencrypted
          # XBOOTLDR partition.
          priority = 1;
          label = "NIXOS-ESP";
          size = "2G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [
              # FAT cannot record POSIX ownership. These masks keep the ESP
              # root-only at runtime; UEFI firmware does not observe them.
              "fmask=0077"
              "dmask=0077"
            ];
          };
        };

        cryptroot = {
          label = "NIXOS-CRYPTROOT";
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";

            # LUKS2 is required for systemd-cryptenroll TPM2 tokens. Argon2id
            # gives a memory-hard interactive passphrase KDF while leaving
            # cryptsetup to calibrate its cost safely for this hardware.
            extraFormatArgs = [
              "--type"
              "luks2"
              "--pbkdf"
              "argon2id"
            ];

            settings = {
              # The NVMe supports deterministic discard. Passing TRIM through
              # LUKS preserves SSD maintenance and the current desktop's trim
              # behaviour, but reveals which encrypted sectors are unused. It
              # never reveals plaintext. Disable this if hiding allocation
              # patterns outweighs trim performance and SSD wear management.
              allowDiscards = true;
            };

            content = {
              type = "btrfs";
              extraArgs = [
                "-f"
                "-L"
                "nixos"
              ];

              subvolumes = {
                "@root" = {
                  mountpoint = "/";
                  mountOptions = btrfsMountOptions;
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = btrfsMountOptions;
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = btrfsMountOptions;
                };
                "@var" = {
                  mountpoint = "/var";
                  mountOptions = btrfsMountOptions;
                };
                "@log" = {
                  # Keep logs when restoring a root or /var snapshot: they are
                  # essential to diagnosing why a generation was rolled back.
                  mountpoint = "/var/log";
                  mountOptions = btrfsMountOptions;
                };
                "@snapshots" = {
                  # A snapshot target is provisioned now, but snapshots remain
                  # a local recovery feature, not a substitute for backups.
                  mountpoint = "/.snapshots";
                  mountOptions = btrfsMountOptions;
                };
                "@swap" = {
                  mountpoint = "/swap";
                  # btrfs filesystem mkswapfile sets the required NOCOW and
                  # extent properties. This swapfile is encrypted because it
                  # sits below cryptroot, unlike the current GPT swap partition.
                  swap.swapfile = {
                    size = "8G";
                    # Existing zram has priority 5. This is only an overflow
                    # fallback, matching the live machine's current policy.
                    priority = -1;
                    options = [ "nofail" ];
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  # Disko creates the Btrfs swapfile above. Pin the NixOS activation entry
  # explicitly: the current Disko release's generated swapfile entry omits the
  # optional `label` option, which recent NixOS swap evaluation attempts to
  # inspect even though a swapfile has no block-device label.
  swapDevices = lib.mkForce [
    {
      device = "/swap/swapfile";
      priority = -1;
      options = [ "nofail" ];
    }
  ];
}
