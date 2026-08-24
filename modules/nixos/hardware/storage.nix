{ config, lib, ... }: {
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
      # These are userspace-accessible and common interchange filesystems.
      # The boot/root filesystem and any initrd storage stack remain host-local:
      # do not place tools and drivers for every removable-media format in an
      # early-boot environment that only needs to unlock and mount the root.
      inherit supportedFilesystems;
    };

  services = {
    # Desktop storage UX.  GVfs provides the GIO volume monitor and FUSE-backed
    # virtual filesystems, while Tumbler provides on-demand thumbnails.  They
    # are defaults rather than requirements, so a headless or locked-down host
    # can disable either without fighting this module.
    gvfs.enable = lib.mkDefault true;
    tumbler.enable = lib.mkDefault true;

    udisks2 = {
      # UDisks supplies polkit-mediated operations for the active local user.
      # It is deliberately not enabled in containers, where block-device
      # management is a host responsibility.
      enable = lib.mkDefault (!config.boot.isContainer);

      # Keep removable media in UDisks' ACL-controlled /run/media/$USER/
      # hierarchy instead of globally shared, persistent /media/.  This does
      # not install an automounter: a user must still request a mount through a
      # file manager or `udisksctl`.
      mountOnMedia = lib.mkDefault false;

      # State the two security/UX defaults intentionally.  LUKS2 is the modern
      # format for new removable encrypted volumes; UDisks loads optional
      # backend modules only when a device actually needs them.
      settings."udisks2.conf" = {
        defaults.encryption = "luks2";
        udisks2 = {
          modules = [ "*" ];
          modules_load_preference = "ondemand";
        };
      };
    };
  };
}
