{ modules, ... }:
{
  system = "x86_64-linux";
  username = "ianmh";
  homeDirectory = "/home/ianmh";
  uid = 1000;

  nixpkgsArgs = {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
    };
  };

  modules = with modules; [
    ## Base
    meta
    nix-settings
    xdg

    ## Shells
    shells-aliases
    shells-starship
    shells-carapace
    shells-eza

    ## Development
    dev-direnv

    ## Programs
    server-ssh

    ## Per-host configuration
    ./ssh.nix
    ./secrets.nix
  ];
}
