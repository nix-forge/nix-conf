{
  lib,
  modules,
  inputs,
  ...
}:
{
  system = "x86_64-linux";
  username = "ianmh";
  homeDirectory = "/home/ianmh";
  uid = 1000;
  # nix-seal's plaintext runtime is mounted and managed by NixOS. Do not
  # expose an independent activation that cannot preserve its noswap guarantee.
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
    xdg
    nixSeal

    fonts
    desktop-optional-emoji-fonts
    desktop-dictation
    dev
    xdg-portal

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
    cli-ripgrep

    shells-aliases
    shells-atuin
    shells-bash
    shells-starship
    shells-carapace
    shells-eza
    shells-fzf
    shells-integration
    shells-tmux
    shells-zoxide

    wm-hyprland
    desktop
    ssh
    services-ssh-forwards
    services-workstation-jobs
    dev-jj-identity

    firefox
    zen-browser
    helium-browser
    chrome

    vscode
    vscode-languages
    vscode-ai
    vscode-defaultvisual
    neovim
    neovim-defaulteditor

    terminals-ghostty
    terminals-ghostty-defaultterminal
    mpv
    moonfin
    feishin

    stylix
    stylix-targets-zen-browser

    discord
    signal
    zoom
    spotify
    bitwarden
    lightcraft
    prismlauncher

  ];

}
