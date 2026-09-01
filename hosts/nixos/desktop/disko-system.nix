{ inputs, ... }: {
  # Import this module into the desktop configuration only from the offline
  # installer, after `disko.nix` has formatted the SSD. It must not be added to
  # the deployed host before migration: the live root is not /dev/mapper/cryptroot.
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
  ];

  # The deployed host's local filesystem module uses this explicit switch to
  # retire its label-based plaintext root and swap declarations.
  hardware.storage.encryptedRoot.enable = true;
}
