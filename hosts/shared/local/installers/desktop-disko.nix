{
  lib,
  systemDisk ? "/dev/disk/by-id/UNCONFIGURED-SYSTEM",
  dataDisk ? "/dev/disk/by-id/UNCONFIGURED-DATA",
  ...
}:
(import ../../../nixos/desktop/local/storage/disk-layout.nix { }).lib.desktopDiskLayout {
  inherit lib systemDisk dataDisk;
}
