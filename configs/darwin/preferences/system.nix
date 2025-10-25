{
  system.defaults = {
    CustomUserPreferences = {
      # Screenshot settings
      "com.apple.screencapture" = {
        # Disable shadow in screenshots
        "disable-shadow" = true;
      };

      # Login Window settings
      "com.apple.loginwindow" = {
        # Disable automatic relaunch of apps on login
        LoginwindowLaunchesRelaunchApps = false;
        # Don't restore windows from previous session
        TALLogoutSavesState = false;
      };
    };
  };
}
