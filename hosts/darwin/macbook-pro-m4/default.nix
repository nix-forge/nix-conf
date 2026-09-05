{ modules, inputs, ... }: {
  system = "aarch64-darwin";
  hostName = "Ian-MBP";

  secrets = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTE/d4MlNXECP5e/1Gi1u0so7wdoy1XtDotVE27P2rZ";
  };

  nixpkgsArgs = {
    overlays = [ inputs.nixpkgs-personal.overlays.default ];
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
    ./local/firewall.nix

    security
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
      description = "Ian Holloway";
      shell = inputs.nixpkgs.legacyPackages.aarch64-darwin.bashInteractive;
    };
  };
}
