{ modules, ... }:
{
  system = "aarch64-darwin";
  username = "ianmh";
  homeDirectory = "/Users/ianmh";
  uid = 501;
  sshPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3PjFNVCaBfwUJIKjQeBoK2kz0VaLdNAQVUb5pJdPPf";

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

    fonts
    dev
    macos
    xdg
    cli

    window-managers-aerospace
    server-ssh

    firefox
    firefox-scrolling-natural
    firefox-defaultbrowser

    vscode
    vscode-languages
    vscode-ai
    vscode-defaultvisual
    neovim
    neovim-defaulteditor

    shells
    shells-nushell-defaultshell
    terminals-ghostty
    terminals-ghostty-defaultterminal

    stylix
    stylix-targets-firefox

    extra-config
  ];
}
