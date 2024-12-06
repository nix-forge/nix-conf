{ lib, ... }:
{
  # Set of base kernel modules to include in the initrd
  # Found here: https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/system/boot/kernel.nix
  boot.initrd.includeDefaultModules = lib.mkForce true;

  boot.initrd.availableKernelModules = [
    "usb_storage" # USB storage devices
    "uas" # USB storage devices
    "rtsx_pci_sdmmc" # Realtek PCI-E SD/MMC Card Host Driver
    "snd_hda_intel" # Intel HD Audio
  ];
}
