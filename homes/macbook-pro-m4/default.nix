{ modules, inputs, ... }:
let
  actualServerCaseFixOverlay = _final: prev: {
    actual-server = prev.actual-server.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        ln -s themes~nix~case~hack~1 packages/component-library/src/themes
        mkdir -p packages/desktop-client/src/style/themes
        cp \
          packages/component-library/src/themes~nix~case~hack~1/dark.css \
          packages/component-library/src/themes~nix~case~hack~1/light.css \
          packages/component-library/src/themes~nix~case~hack~1/midnight.css \
          packages/component-library/src/themes~nix~case~hack~1/palette.css \
          packages/desktop-client/src/style/themes/
        substituteInPlace packages/desktop-client/src/style/theme.tsx \
          --replace-fail "@actual-app/components/themes/dark.css?inline" "./themes/dark.css?inline" \
          --replace-fail "@actual-app/components/themes/light.css?inline" "./themes/light.css?inline" \
          --replace-fail "@actual-app/components/themes/midnight.css?inline" "./themes/midnight.css?inline" \
          --replace-fail "@actual-app/components/themes/palette.css?inline" "./themes/palette.css?inline"
      '';
    });
  };
in
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
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3PjFNVCaBfwUJIKjQeBoK2kz0VaLdNAQVUb5pJdPPf";
  };

  nixpkgsArgs = {
    overlays = [
      inputs.nixpkgs-personal.overlays.default
      actualServerCaseFixOverlay
    ];
    config = {
      allowUnfree = true;
    };
  };

  modules = with modules; [
    # Compatibility value for this Home Manager installation; do not raise it
    # merely to follow the current Nixpkgs/Home Manager release.
    { home.stateVersion = "25.05"; }

    ## Base
    determinate
    nix-settings
    registry
    browser-policies
    cache
    nixSeal
    ./nix-seal.nix
    ./local/containers.nix
    ./local/moonlight.nix
    macos

    fonts
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
        environmentFile = config.nixSeal.secrets."service-runtime-environment".path;
      };
      # Retain the host-only VM diagnostics and SSH helpers that accompany the
      # control host.
      services.devVm.enable = true;
    })

    firefox
    firefox-scrolling-natural
    helium-browser
    zen-browser
    zen-browser-scrolling-natural
    zen-browser-defaultbrowser
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
        menuBarVisibility = "always";
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

    steam-darwin
    moonlight
    prismlauncher
  ];
}
