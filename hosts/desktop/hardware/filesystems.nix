{ config, lib, ... }:
let
  rootLabel = "nixos";
  bootLabel = "boot";
  swapLabel = "swap";

  # function to easily duplicate a btrfs automount scheme
  # NOTE: when creating partitions these mount options should be used
  # NOTE: ideally use @ in front of the subvol name to distinguish it from a regular directory
  btrfsAuto = device: subvol: {
    inherit device;
    fsType = "btrfs";
    options = [
      "subvol=${subvol}"
      "compress-force=zstd:1"
      "noatime"
    ];
  };
in
{
  # Define the filesystems and their mount points
  fileSystems =
    let
      rootDisk = "/dev/disk/by-label/${rootLabel}";
    in
    {
      "/" = btrfsAuto rootDisk "@root";
      "/var" = btrfsAuto rootDisk "@var";
      "/tmp" = btrfsAuto rootDisk "@tmp";
      "/nix" = btrfsAuto rootDisk "@nix";
      "/home" = btrfsAuto rootDisk "@home";

      ${config.boot.loader.efi.efiSysMountPoint} = {
        device = "/dev/disk/by-label/${bootLabel}";
        fsType = "vfat";
      };

      "/run/media/ianmh/games" = btrfsAuto "/dev/disk/by-label/games" "games";
    };

  # Enable BTRFS srub support
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  # Enable a swap partition
  swapDevices = [ { label = swapLabel; } ];
  boot.resumeDevice = "/dev/disk/by-label/${swapLabel}";

  # Set boot loader EFI system mount point
  boot.loader.efi.efiSysMountPoint = "/boot";

  # Enable SSD TRIM support
  services.fstrim.enable = lib.mkDefault true;

  # Allow Nix to automatically optimise the store
  # NOTE: On ZFS fs set this to false as we never want to
  # allow nix to create hard-links because the filesystem takes care of that
  nix.settings.auto-optimise-store = true;
}
### FILESYSTEM SETUP INSTRUCTIONS ON INSTALL ###
# TODO: FIX THIS IT IS WRONG HOWEVER SOME PARTS ARE RIGHT
/*
  1. Create the partitions root, boot, and swap
  2. Format the partitions (edit these commands for this step to use the correct partition names)
    - NOTE: Create a nix-shell with btrfs-progs "nix-shell -p btrfs-progs" you will need to connect to the internet to download the package
    - root: mkfs.btrfs -L nixos /dev/${the root partition}
    - boot: mkfs.vfat -F 32 -n boot /dev/${the boot partition}
    - swap: mkswap -L swap /dev/${the swap partition}
  3. Create Directories on the /mnt
    - mkdir -p /mnt/{var,tmp,nix,home,boot}
    - create any other directories you need for subvolumes
  4. Mount the partitions
    - root: mount /dev/disk/by-label/nixos /mnt
    - boot: mount /dev/disk/by-label/boot /mnt/boot
    - swap: swapon /dev/disk/by-label/swap
  5. Create the btrfs subvolumes
    - btrfs subvolume create /mnt/{@root,@var,@tmp,@nix,@home}
    - create any other subvolumes you need
    - unmount the root partition: umount /mnt
  6. Mount the btrfs subvolumes and the boot partition and turn on swap
    - mount -o compress-force=zstd:1,noatime,subvol=@root /dev/disk/by-label/nixos /mnt
    - mount -o compress-force=zstd:1,noatime,subvol=@var /dev/disk/by-label/nixos /mnt/var
    - mount -o compress-force=zstd:1,noatime,subvol=@tmp /dev/disk/by-label/nixos /mnt/tmp
    - mount -o compress-force=zstd:1,noatime,subvol=@nix /dev/disk/by-label/nixos /mnt/nix
    - mount -o compress-force=zstd:1,noatime,subvol=@home /dev/disk/by-label/nixos /mnt/home
    - mount /dev/disk/by-label/boot /mnt/boot
    - swapon /dev/disk/by-label/swap
  7. Run the nixos-install command (edit the path to the flake and the host of the flake)
    - Make sure you are connected to the internet
    - nixos-install --flake "$(path)#$(hostname)" --no-root-password --cores "$(($(nproc)/4))" -j 4
  8. Reboot the system
*/
