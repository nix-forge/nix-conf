{
  config,
  inputs,
  lib,
  ...
}:
{
  imports = [ inputs.disko.nixosModules.disko ];

  # Always import the module, but switch layouts only in the offline install.
  # Normal rebuilds need no private physical drive identifiers: Disko derives
  # mounts from GPT labels and LUKS mapper names.
  config = lib.mkIf config.hardware.storage.encryptedRoot.enable (
    import ./disko.nix { inherit lib; }
  );
}
