{ lib, config, ... }:
let
  btrfsMounts = lib.filterAttrs (_: mount: mount.fsType == "btrfs") config.fileSystems;
in
{
  # enable docker
  virtualisation.docker = {
    enable = true;

    # start dockerd on boot.
    # This is required for containers which are created with the `--restart=always` flag to work.
    enableOnBoot = true;

    # enable storage driver if btrfs is used
    storageDriver = lib.mkIf (btrfsMounts != { }) "btrfs";

    # enable rootless mode
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };
}
