{ modules, connectHomeDarwin, ... }:
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
    (connectHomeDarwin "ianmh@macbook-pro-m4" { })

    ## Homebrew
    homebrew
    homebrew-casks
    homebrew-brews

    ## Preferences
    preferences # TODO: try to move to home-manager

    ## Security
    security

    ## Secrets
    secrets
  ];
}
