{ modules, ... }:
{
  system = "x86_64-linux";
  username = "ianmh";
  homeDirectory = "/home/ianmh";
  uid = 1000;
  sshPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEolRZAKwwqDLSkgezpqNK4WYLjMsE1qp8f3k7nYMVgq";

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
    agenix

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
  ];
}
