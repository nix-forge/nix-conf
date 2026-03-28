{ config, inputs, ... }:
{
  imports = [ inputs.disko.nixosModules.disko ];

  assertions = [
    {
      assertion = config.disko.devices.disk.main.device != null;
      message = "disko.devices.disk.main.device must be set to the device path of the main disk (e.g. /dev/sda).";
    }
  ];

  disko.devices.disk.main = {
    type = "disk";
    # device = --- SET IN HOST CONFIG ---;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          label = "ESP";
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };

        cryptroot = {
          label = "cryptroot";
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            settings.allowDiscards = true;

            content = {
              type = "btrfs";
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
                "@log" = {
                  mountpoint = "/var/log";
                  mountOptions = [
                    "compress-force=zstd:1"
                    "noatime"
                  ];
                };
                "@persist" = {
                  mountpoint = "/persist";
                  mountOptions = [
                    "compress-force=zstd:1"
                    "noatime"
                  ];
                };
                "@tmp" = {
                  mountpoint = "/tmp";
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

}
