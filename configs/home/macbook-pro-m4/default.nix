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

    { programs.ripgrep.enable = true; }
    { home.sessionVariables.EDITOR = "nvim"; }
    { home.sessionVariables.VISUAL = "code"; }
    { home.sessionVariables.TERMINAL = "ghostty"; }

    ({ pkgs, ... }: install pkgs.bun)
    ({ pkgs, ... }: install pkgs.nixfmt)
    ({ pkgs, ... }: install pkgs.just)
    ({ pkgs, ... }: install pkgs.shfmt)
    ({ pkgs, ... }: install pkgs.shellcheck)

    extra-config
    secrets
  ];
}
