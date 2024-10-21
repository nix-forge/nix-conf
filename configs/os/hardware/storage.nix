{ config, ... }:
{
  boot =
    let
      supportedFilesystems = [
        "vfat"
        "ext4"
        "btrfs"
        "exfat"
        "ntfs"
      ];
    in
    {
      supportedFilesystems = supportedFilesystems;
      initrd = {
        supportedFilesystems = supportedFilesystems;
      };
    };

  services = {
    # enable GVfs, a userspace virtual filesystem.
    gvfs.enable = true;

    # Thumbnail support for images
    tumbler.enable = true;

    # storage daemon required for udiskie auto-mount
    udisks2 = {
      enable = !config.boot.isContainer;
      settings = {
        # general udisks2 configuration
        "udisks2.conf" = {
          defaults = {
            encryption = "luks2"; # alternatively, luks1
          };

          udisks2 = {
            modules = [ "*" ];
            modules_load_preference = "ondemand";
          };
        };
      };
    };
  };
}
