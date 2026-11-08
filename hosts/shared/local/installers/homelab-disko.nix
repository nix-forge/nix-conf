{
  lib,
  homelabDisk ? "/dev/disk/by-id/usb-UNCONFIGURED-HOMELAB",
  ...
}:
(import ../../../nixos/desktop/local/storage/homelab-disk-layout.nix { }).lib.homelabDiskLayout {
  inherit lib homelabDisk;
}
