{ config, lib, ... }: {
  # Loader selection, firmware mode, installation target, and NVRAM writes
  # are properties of a host. This shared policy applies only after a host has
  # explicitly selected GRUB.
  config = lib.mkIf config.boot.loader.grub.enable {
    boot.loader.grub.configurationLimit = lib.mkDefault 12;
  };
}
