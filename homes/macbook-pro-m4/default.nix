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
  darwinBuildFixOverlay = final: prev: {
    oxlint = prev.oxlint.overrideAttrs {
      # napi-rs 3.8.2 probes /bin/ps after compiling, which the Darwin sandbox
      # rejects. Build the same cdylib directly and reuse the checked-in NAPI
      # bindings before running oxlint's normal JavaScript bundle step.
      buildPhase = ''
        runHook preBuild

        (
          cd apps/oxlint
          cargo build \
            --release \
            --features allocator \
            --target ${final.stdenv.hostPlatform.rust.rustcTarget}
        )
        cp \
          target/${final.stdenv.hostPlatform.rust.rustcTarget}/release/liboxlint.dylib \
          apps/oxlint/src-js/oxlint.darwin-arm64.node
        pnpm --filter oxlint-app run build-js

        runHook postBuild
      '';
    };
    darktable = prev.darktable.overrideAttrs (old: {
      versionCheckProgram = "${placeholder "out"}/bin/darktable-cli";
      versionCheckProgramArg = "--version";
      versionCheckKeepEnvironment = "HOME";
      preVersionCheck = (old.preVersionCheck or "") + ''
        export HOME="$TMPDIR"
        mkdir -p "$HOME/.config/darktable"
      '';
    });
    libgphoto2 = prev.libgphoto2.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [ final.gettext ];
      NIX_LDFLAGS = "-lintl";
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
  };

  nixpkgsArgs = {
    overlays = [
      inputs.nixpkgs-personal.overlays.default
      actualServerCaseFixOverlay
      darwinBuildFixOverlay
    ];
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
    nixSeal
    ./nix-seal.nix
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
    server-ssh
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
    ({ pkgs, ... }: { home.packages = [ pkgs.xirp ]; })

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
