{ modules, ... }: {
  system = "x86_64-linux";
  username = "ianmh";
  homeDirectory = "/home/ianmh";
  uid = 1000;

  secrets = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEolRZAKwwqDLSkgezpqNK4WYLjMsE1qp8f3k7nYMVgq";
  };

  nixpkgsArgs = {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
    };
  };

  modules = with modules; [
    # Compatibility value for this Home Manager installation; do not raise it
    # merely to follow the current Nixpkgs/Home Manager release.
    { home.stateVersion = "25.05"; }

    ## Base
    determinate
    nix-settings
    registry
    xdg
    steam-library
    nixSeal
    ./nix-seal.nix

    ## Shells
    shells-aliases
    shells-starship
    shells-carapace
    shells-eza
    shells-tmux

    ## Development
    dev-direnv

    ## Programs
    # The desktop host boots straight into Hyprland for headless Sunshine.
    wm-hyprland
    server-ssh
    mpv
    spotify
    libreoffice
    { programs.libreoffice.enable = true; }
    helium-browser
    zen-browser
    zen-browser-scrolling-natural
    zen-browser-defaultbrowser

  ];
}
