{ modules, ... }:
let
  install = pkg: { home.packages = [ pkg ]; };
in
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
    cache
    xdg
    agenix
    macos
    { programs.nh.enable = true; }

    fonts
    dev
    shells
    shells-nushell-defaultshell
    window-managers-aerospace
    firefox
    firefox-scrolling-natural
    firefox-defaultbrowser
    server-ssh
    terminals-ghostty
    vscode
    vscode-languages
    vscode-ai
    neovim
    stylix
    stylix-targets-firefox
    ({ pkgs, ... }: install pkgs.n8n)

    { programs.ripgrep.enable = true; }
    { home.sessionVariables.EDITOR = "nvim"; }
    { home.sessionVariables.VISUAL = "code"; }
    { home.sessionVariables.TERMINAL = "ghostty"; }

    extra-config
  ];
}
