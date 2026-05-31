{ modules, ... }:
# let
#   darwinOpenSslTestOverlay = final: prev: {
#     openssl = prev.openssl.overrideAttrs (old: {
#       postPatch =
#         (old.postPatch or "")
#         + final.lib.optionalString final.stdenv.hostPlatform.isDarwin ''
#           rm -f test/recipes/70-test_sslmessages.t
#         '';
#     });
#   };
# in
{
  system = "aarch64-darwin";
  # darwinSdkVersion = "15.5";
  # darwinMinVersion = "15.4";
  username = "ianmh";
  homeDirectory = "/Users/ianmh";
  uid = 501;

  secrets = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3PjFNVCaBfwUJIKjQeBoK2kz0VaLdNAQVUb5pJdPPf";
    groups = [ "IanHollow" ];
  };

  nixpkgsArgs = {
    # overlays = [ darwinOpenSslTestOverlay ];
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
    zen-browser
    zen-browser-scrolling-natural
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
    stylix-targets-zen-browser

    discord
    signal
    zoom
    spotify
    notion
    bitwarden

    steam-darwin
    prismlauncher

    extra-config
  ];
}
