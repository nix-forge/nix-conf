{ modules, ... }:
let
  install = pkg: { home.packages = [ pkg ]; };
in
{
  system = "aarch64-darwin";
  username = "ianmh";
  homeDirectory = "/Users/ianmh";
  uid = 501;

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

    ({ pkgs, ... }: install pkgs.neovim)
    { home.sessionVariables.EDITOR = "nvim"; }
    { home.sessionVariables.VISUAL = "code"; }

    extra-config
    secrets
  ];
}
