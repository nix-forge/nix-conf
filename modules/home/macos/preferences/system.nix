{
  targets.darwin.defaults = {
    "com.apple.screencapture"."disable-shadow" = true;

    "com.apple.loginwindow" = {
      LoginwindowLaunchesRelaunchApps = false;
      TALLogoutSavesState = false;
    };
  };
}
