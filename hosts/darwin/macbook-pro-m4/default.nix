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

  nixpkgsArgs = {
    overlays = [ (import ../../../overlays { inherit inputs; }) ];
    config = {
      allowUnfree = true;
    };
  };

  modules = with modules; [
    { system.primaryUser = "ianmh"; }
    # Original nix-darwin compatibility generation for this installation.
    # Raising this is a migration decision, not a routine upgrade.
    { system.stateVersion = 6; }

    ## Base
    determinate
    nix-settings
    registry
    cache
    chromium-policies
    nixSeal
    ./nix-seal.nix

    security
    yubikey
    macos
    stylix
    fonts
    ssh
    # nix-darwin defaults this to false. Link system package completions so
    # Bash users outside Home Manager receive packaged completions as well.
    { programs.bash.completion.enable = true; }
  ];

  homes.ianmh = {
    config = "ianmh@macbook-pro-m4";
    user = {
      description = "IanHollow";
      shell = inputs.nixpkgs.legacyPackages.aarch64-darwin.bashInteractive;
    };
  };
}
