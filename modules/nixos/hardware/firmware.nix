{ lib, config, ... }: {
  hardware = {
    # Include firmware that can be redistributed by Nixpkgs.  Do not enable
    # `enableAllFirmware` here: a host that needs a non-redistributable blob
    # should declare that specific requirement locally instead of expanding
    # every system's firmware trust and closure.
    enableRedistributableFirmware = lib.mkDefault true;
  };

  services.fwupd = {
    # fwupd refreshes signed LVFS metadata on its upstream persistent,
    # randomized timer.  It never installs firmware without an explicit
    # privileged `fwupdmgr` action, so this is safe as a shared default.
    enable = lib.mkDefault true;

    daemonSettings.EspLocation = lib.mkDefault config.boot.loader.efi.efiSysMountPoint;

    # Remove staged capsule files and EFI variables after a reboot.  Keep
    # vendor defaults for the capsule delivery mechanism, Secure Boot shim,
    # remotes, and trusted keys: changing any of those requires host- and
    # vendor-specific evidence.
    uefiCapsuleSettings.RebootCleanup = lib.mkDefault true;
  };
}
