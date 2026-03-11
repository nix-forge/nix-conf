{ config, lib, ... }:
{
  targets.darwin.defaults = {
    "com.apple.screencapture" = {
      disable-shadow = true;
      clipboard = false;
      target = "file";
    }
    // lib.optionalAttrs (
      config.xdg.enable
      && config.xdg.userDirs.enable
      && config.xdg.userDirs.extraConfig ? "SCREENSHOTS"
      && config.xdg.userDirs.extraConfig.SCREENSHOTS != null
    ) { location = config.xdg.userDirs.extraConfig.SCREENSHOTS; };

    "com.apple.loginwindow" = {
      LoginwindowLaunchesRelaunchApps = false;
      TALLogoutSavesState = false;
    };
  };
}
