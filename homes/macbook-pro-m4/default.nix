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

  nixpkgsArgs = {
    overlays = [ (import ../../overlays { inherit inputs; }) ];
    config = {
      allowUnfree = true;
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
    nixSeal
    ./nix-seal.nix
    macos

    fonts
    desktop-optional-emoji-fonts
    dev
    xdg
    cli

    wm-aerospace
    actual
    ({ config, ... }: {
      services.actual = {
        enable = false;
        dataDir = "${config.xdg.userDirs.documents}/Actual";
      };
    })
    karakeep
    ({ config, ... }: {
      services.karakeep = {
        enable = false;
        dataDir = "${config.xdg.userDirs.documents}/Karakeep";
      };
    })
    ssh
    ({ config, ... }: {
      services.localControl = {
        enable = true;
        environmentFile = config.nixSeal.secrets.service-private-settings.path;
      };
      # Retain the host-only VM diagnostics and SSH helpers that accompany the
      # control host.
      services.devVm.enable = true;
    })

    firefox
    helium-browser
    zen-browser
    chrome

    vscode
    vscode-languages
    vscode-ai
    vscode-defaultvisual
    neovim
    neovim-defaulteditor

    shells
    terminals-ghostty
    terminals-ghostty-defaultterminal
    mpv
    libreoffice
    { programs.libreoffice.enable = true; }
    vorssaint
    {
      programs.vorssaint = {
        enable = true;
        startAtLogin = true;
        acknowledgeFanControlLimitation = true;
      };
    }
    linearmouse
    {
      programs.linearmouse = {
        enable = true;
        menuBarVisibility = "never";
        menuBarBatteryDisplay = "off";
        showInDock = false;
        settings = {
          schemes = [
            {
              "if" = {
                device = {
                  category = "mouse";
                };
              };
              pointer = {
                # Keep macOS's adaptive acceleration and the device/system
                # tracking speed. A numeric acceleration of 0 is not the same
                # as disabling acceleration in LinearMouse.
                acceleration = "unset";
                speed = "unset";
                disableAcceleration = false;
              };
              scrolling = {
                reverse = {
                  vertical = true;
                };
              };
            }
          ];
        };
      };
    }

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
    darktable
    wootility

    steam-darwin
    moonlight
    prismlauncher
  ];

}
