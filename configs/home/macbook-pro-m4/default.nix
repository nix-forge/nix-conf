{ modules, ... }:
{
  system = "aarch64-darwin";
  username = "ianmh";
  homeDirectory = "/Users/ianmh";
  uid = 501;

  secrets = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3PjFNVCaBfwUJIKjQeBoK2kz0VaLdNAQVUb5pJdPPf";
    groups = [ "IanHollow" ];
  };

  nixpkgsArgs = {
    config = {
      allowUnfree = true;
    };
  };

  modules = with modules; [
    ## Base
    meta
    determinate
    nix-settings
    registry
    cache
    agenix
    macos

    fonts
    dev
    xdg
    cli

    wm-aerospace
    server-ssh

    firefox
    firefox-scrolling-natural
    firefox-defaultbrowser
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

    stylix
    stylix-targets-firefox

    discord
    whatsapp
    signal
    zoom
    spotify
    notion
    bitwarden

    steam-darwin

    extra-config
  ];
}
