{ lib, pkgs, ... }:
let
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
      arRPC = false;
      checkUpdates = false;
      hardwareAcceleration = true;
      discordBranch = "stable";
    };
  };
}
