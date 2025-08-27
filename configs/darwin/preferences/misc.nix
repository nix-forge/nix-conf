{
  system.defaults = {
    # disable the "Are you sure you want to open this application?" dialog
    LaunchServices.LSQuarantine = false;

    NSGlobalDomain = {
      # expand save panel by default
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
    };

    CustomUserPreferences = {
      # Add a context menu item for showing the Web Inspector in web views
      NSGlobalDomain.WebKitDeveloperExtras = true;

      "com.apple.desktopservices" = {
        # Avoid creating .DS_Store files on network or USB volumes
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };

      "com.apple.AdLib".allowApplePersonalizedAdvertising = false;
    };
  };
}
