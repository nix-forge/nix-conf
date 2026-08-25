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
    nixSeal
    ./nix-seal.nix

    fonts
    dev
    xdg

    # Keep the workstation's command-line tools explicit. `cli-whisper`
    # brings a machine-learning runtime and is intentionally opt-in rather
    # than an implicit dependency of every desktop Home Manager generation.
    cli-ffmpeg
    cli-hf
    cli-images
    cli-jq
    cli-nh
    cli-pandoc
    cli-pdf
    cli-remindctl
    cli-ripgrep

    shells-aliases
    shells-starship
    shells-carapace
    shells-eza
    shells-tmux

    wm-hyprland
    server-ssh
    spotify

    zen-browser
    zen-browser-scrolling-natural
    zen-browser-defaultbrowser
    helium-browser
    chrome

    vscode
    vscode-languages
    vscode-ai
    vscode-defaultvisual
    neovim
    neovim-defaulteditor

    shells
    shells-tmux
    shells-nushell-defaultshell
    terminals-ghostty
    terminals-ghostty-defaultterminal
    mpv
    libreoffice
    { programs.libreoffice.enable = true; }

    stylix
    stylix-targets-zen-browser

    discord
    signal
    zoom
    spotify
    bitwarden
    darktable

    steam-library
  ];
}
