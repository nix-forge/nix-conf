{
  pkgs,
  lib,
  config,
  ...
}:
{
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  # firmware updater for machine hardware
  services.fwupd = {
    enable = true;
    daemonSettings.EspLocation = config.boot.loader.efi.efiSysMountPoint;
  };
}
