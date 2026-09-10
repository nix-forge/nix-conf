{ lib, ... }: {
  # Change only in the installer copy after backing up and formatting both
  # target drives. A normal rebuild must keep the current layout until then.
  hardware.storage.encryptedRoot = {
    enable = lib.mkDefault false;
    unlockMethod = lib.mkDefault "passphrase";
  };
}
