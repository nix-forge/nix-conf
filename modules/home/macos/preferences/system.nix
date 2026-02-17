_: {
  targets.darwin.defaults = {
    "com.apple.screencapture" =
      {
        disable-shadow = true;
        clipboard = true;
      }
    # // lib.optionalAttrs (config.xdg.enable && config.xdg.userDirs.enable) {
    #   location = config.xdg.userDirs.pictures + "/Screenshots";
    # }
    ;

    "com.apple.loginwindow" = {
      LoginwindowLaunchesRelaunchApps = false;
      TALLogoutSavesState = false;
    };
  };
}
