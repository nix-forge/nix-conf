{
  modules,
  inputs,
  lib,
  ...
}:
{
  system = "aarch64-darwin";
  username = "ianmh";
  homeDirectory = "/Users/ianmh";
  uid = 501;
  # nix-seal's plaintext runtime is mounted and managed by nix-darwin. Do not
  # expose an independent activation that would fall back to persistent cache
  # storage in the user profile.
  standalone = false;

  secrets = {
    publicKey = lib.removeSuffix "\n" (builtins.readFile ./local/nix-seal/identity.pub);
  };

  nixpkgsArgs = (import ./local/package-policy.nix { }).lib.targetPackagePolicy inputs;

  modules = with modules; [

    ## Base
    determinate
    nix-settings
    registry
    cache
    nixSeal

    macos

    fonts
    desktop-optional-emoji-fonts
    desktop-dictation
    dev
    xdg
    cli

    wm-rift
    actual
    ssh
    services-ssh-forwards
    services-workstation-jobs
    dev-jj-identity

    firefox
    helium-browser
    zen-browser
    chrome

    vscode
    vscode-languages
    vscode-languages-rust
    vscode-ai
    vscode-defaultvisual
    neovim
    neovim-defaulteditor

    shells
    terminals-ghostty
    terminals-ghostty-defaultterminal
    mpv
    moonfin
    feishin
    vorssaint
    linearmouse

    stylix
    stylix-targets-firefox
    stylix-targets-zen-browser

    discord
    signal
    zoom
    microsoft-teams
    spotify
    notion
    bitwarden
    lightcraft
    wootility

    steam-darwin
    prismlauncher
  ];

}
