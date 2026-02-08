{ modules, ... }:
{
  system = "aarch64-darwin";
  hostName = "Ian-MBP";
  sshPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTE/d4MlNXECP5e/1Gi1u0so7wdoy1XtDotVE27P2rZ";

  nixpkgsArgs = {
    config = {
      allowUnfree = true;
    };
  };

  modules = with modules; [
    { system.primaryUser = "ianmh"; }

    ## Base
    meta
    determinate
    nix-settings
    cache
    agenix

    ## Users
    home-manager
    users

    ## Homebrew
    homebrew
    homebrew-casks
    homebrew-brews

    security
    stylix
    fonts
  ];
}
