{ lib, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;

  vesktopPackage =
    if pkgs.stdenv.hostPlatform.isDarwin then
      pkgs.vesktop.overrideAttrs (old: {
        # Explicitly disable macOS signing in electron-builder for arm64-darwin.
        buildPhase =
          lib.replaceStrings
            [ "  -c.electronDist=. \\\n" ]
            [ "  -c.mac.identity=null \\\n  -c.electronDist=. \\\n" ]
            old.buildPhase;
      })
    else
      pkgs.vesktop;
in
{
  programs.vesktop = {
    enable = true;
    package = vesktopPackage;
    vencord = {
      useSystem = true;
      settings = { };
    };

    settings = {
      discordBranch = "stable";
      tray = isLinux;
      minimizeToTray = isLinux;
      autoStartMinimized = false;
      openLinksWithElectron = false;

      hardwareAcceleration = true;
      hardwareVideoAcceleration = true;

      arRPC = false;

      enableSplashScreen = true;
      splashTheming = true;

      checkUpdates = false;
    };
  };
}
