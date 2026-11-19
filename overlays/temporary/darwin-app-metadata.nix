{ lib, ... }: {
  reason = "Selected upstream macOS GUI packages omit meta.mainDarwinApp, so consumers cannot resolve their bundles from package metadata.";
  upstream = "https://github.com/NixOS/nixpkgs/tree/b3cff76391a4867236cc135b69a928d873b9f6d0/pkgs";
  removal = "The selected upstream recipes declare mainDarwinApp matching their installed top-level bundles; remove each mapping as its recipe gains metadata.";
  reviewedRevision = "04906337b6d53e8bb0eaf0470ae9f070a4d4eb55";
  inputPath = [ "nixpkgs" ];
  apply =
    packages:
    lib.mapAttrs
      (
        name: bundle:
        packages.${name}.overrideAttrs (old: {
          meta = {
            mainDarwinApp = bundle;
          }
          // (old.meta or { });
        })
      )
      {
        chatgpt = "ChatGPT.app";
        code-cursor = "Cursor.app";
        feishin = "Feishin.app";
        firefox-bin-unwrapped = "Firefox.app";
        ghostty-bin = "Ghostty.app";
        google-chrome = "Google Chrome.app";
        linearmouse = "LinearMouse.app";
        mpv = "mpv.app";
        notion-app = "Notion.app";
        prismlauncher = "PrismLauncher.app";
        signal-desktop = "Signal.app";
        vesktop = "Vesktop.app";
        vscode = "Visual Studio Code.app";
        zoom-us = "zoom.us.app";
      };
}
