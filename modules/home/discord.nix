{ pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  programs.vesktop = {
    enable = true;
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
