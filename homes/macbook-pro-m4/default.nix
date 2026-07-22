{ modules, ... }:
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

  secrets = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3PjFNVCaBfwUJIKjQeBoK2kz0VaLdNAQVUb5pJdPPf";
    groups = [ "IanHollow" ];
  };

  nixpkgsArgs = {
    overlays = [ actualServerCaseFixOverlay ];
    config = {
      allowUnfree = true;
      permittedInsecurePackages = [ "electron-40.10.5" ];
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
    actual
    ({ config, ... }: {
      services.actual = {
        enable = true;
        dataDir = "${config.xdg.userDirs.documents}/Actual";
      };
    })
    karakeep
    ({ config, ... }: {
      services.karakeep = {
        enable = true;
        dataDir = "${config.xdg.userDirs.documents}/Karakeep";
      };
    })
    server-ssh

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
    prismlauncher
  ];
}
