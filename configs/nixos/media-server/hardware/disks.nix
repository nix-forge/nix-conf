{ config, ... }:
let
  cfg = config.my.media;
in
{
  assertions = [
    {
      assertion = cfg.storage.diskId != "";
      message = "Set my.media.storage.diskId in configs/nixos/media-server/modules/site.nix";
    }
  ];

  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/disk/by-id/${cfg.storage.diskId}";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            name = "boot";
            type = "EF00";
            size = "1G";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };

          swap = {
            size = cfg.storage.swapSize;
            content.type = "swap";
          };

          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@root" = {
                  mountpoint = "/";
                  mountOptions = [
                    "compress-force=zstd:1"
                    "noatime"
                  ];
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress-force=zstd:1"
                    "noatime"
                  ];
                };
                "@var" = {
                  mountpoint = "/var";
                  mountOptions = [
                    "compress-force=zstd:1"
                    "noatime"
                  ];
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = [
                    "compress-force=zstd:1"
                    "relatime"
                  ];
                };
                "@srv-media" = {
                  mountpoint = cfg.storage.mediaDir;
                  mountOptions = [
                    "compress-force=zstd:1"
                    "noatime"
                  ];
                };
                "@srv-downloads" = {
                  mountpoint = cfg.storage.downloadsDir;
                  mountOptions = [
                    "compress-force=zstd:1"
                    "noatime"
                  ];
                };
                "@srv-state" = {
                  mountpoint = cfg.storage.stateDir;
                  mountOptions = [
                    "compress-force=zstd:1"
                    "noatime"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };

  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };
}
