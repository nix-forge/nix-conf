{ modules, ... }:
{
  system = "aarch64-darwin";
  hostName = "Ian-MBP";

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

    ## Users
    home-manager
    users

    ## Homebrew
    homebrew
    homebrew-casks
    homebrew-brews

    preferences # TODO: try to move to home-manager
    security
    secrets
    stylix
    fonts
  ];
}
