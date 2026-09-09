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

  nixpkgsArgs = {
    overlays = [ (import ../../overlays { inherit inputs; }) ];
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
    };
  };

  modules = with modules; [
    # Full design library remains a user choice, independent of font roles.
    { typography.designLibrary = "full"; }
    # Compatibility value for this Home Manager installation; do not raise it
    # merely to follow the current Nixpkgs/Home Manager release.
    { home.stateVersion = "25.05"; }

    ## Base
    determinate
    nix-settings
    registry
    cache
    xdg
    nixSeal
    ./nix-seal.nix

    fonts
    ../../modules/home/desktop/optional-emoji-fonts.nix
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
    cli-remindctl
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
    spotify

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
    libreoffice
    {
      programs.libreoffice = {
        enable = true;
        # The matching NixOS policy is declared in the desktop-local
        # AppArmor module; other hosts deliberately remain unconfined.
        languageTool.appArmorProfile = "nixos-languagetool";
      };
    }

    stylix
    stylix-targets-zen-browser

    discord
    signal
    zoom
    spotify
    bitwarden
    darktable
    prismlauncher

  ];

}
