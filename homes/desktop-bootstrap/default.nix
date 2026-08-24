{ modules, ... }: {
  system = "x86_64-linux";
  username = "ianmh";
  homeDirectory = "/home/ianmh";
  uid = 1000;

  secrets.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEolRZAKwwqDLSkgezpqNK4WYLjMsE1qp8f3k7nYMVgq";

  modules = with modules; [
    # Compatibility value for this Home Manager installation; do not raise it
    # merely to follow the current Nixpkgs/Home Manager release.
    { home.stateVersion = "25.05"; }

    determinate
    nix-settings
    cache
    registry
    xdg

    shells-aliases
    shells-starship
    shells-carapace
    shells-eza
    shells-tmux
    server-ssh
  ];
}
