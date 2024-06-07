{ config, ... }:
{
  boot.initrd.availableKernelModules = [
    "nvme"
    "ahci"
    "thunderbolt"
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "ums_realtek"
    "acpi_call"
  ];
  boot.kernelModules = [ "acpi_call" ];
  boot.extraModulePackages = with config.boot.kernelPackages; [ acpi_call ];
}
