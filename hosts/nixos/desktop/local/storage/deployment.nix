{ lib, ... }: {
  # The desktop now boots from the installed Disko layout.
  hardware.storage.encryptedRoot = {
    enable = lib.mkDefault true;
    unlockMethod = lib.mkDefault "tpm-pin";
  };

  # The installer still forces this off for the first boot, before its key is
  # enrolled on encrypted root.
  hardware.storage.homelabHdd.enable = lib.mkDefault true;
}
