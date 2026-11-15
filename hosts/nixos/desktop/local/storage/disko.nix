{
  config,
  inputs,
  lib,
  ...
}:
let
  systemLayout = (import ./disk-layout.nix { }).lib.desktopDiskLayout;
  homelabLayout = (import ./homelab-disk-layout.nix { }).lib.homelabDiskLayout;
in
{
  imports = [ inputs.disko.nixosModules.disko ];

  # Keep internal and removable-disk layouts independently selectable. Normal
  # rebuilds need no physical drive identifiers: Disko derives mounts from GPT
  # labels and LUKS mapper names after each disk has been provisioned.
  config = lib.mkMerge [
    (lib.mkIf config.hardware.storage.encryptedRoot.enable (systemLayout {
      inherit lib;
    }))
    (lib.mkIf config.hardware.storage.homelabHdd.enable (homelabLayout {
      inherit lib;
    }))
  ];
}
