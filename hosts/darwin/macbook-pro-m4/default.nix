{
  lib,
  modules,
  inputs,
  ...
}:
{
  system = "aarch64-darwin";
  hostName = "Ian-MBP";

  secrets = {
    publicKey = lib.removeSuffix "\n" (builtins.readFile ./local/nix-seal/identity.pub);
  };

  nixpkgsArgs = (import ./local/package-policy.nix { }).lib.targetPackagePolicy inputs;

  modules = with modules; [
    # Original nix-darwin compatibility generation for this installation.
    # Raising this is a migration decision, not a routine upgrade.

    ## Base
    determinate
    nix-settings
    codex-runtime
    registry
    cache
    chromium-policies
    nixSeal

    security
    yubikey
    macos
    dictation
    stylix
    fonts
    ssh
    # nix-darwin defaults this to false. Link system package completions so
    # Bash users outside Home Manager receive packaged completions as well.
  ];

  homes.ianmh = {
    config = "ianmh@macbook-pro-m4";
    user = {
      description = "IanHollow";
      shell = inputs.nixpkgs.legacyPackages.aarch64-darwin.bashInteractive;
    };
  };
}
