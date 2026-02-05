{
  system.defaults = {
    # Screensaver - Require password immediately after sleep
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 0;
    };

    CustomUserPreferences = {
      # Show remaining battery time; hide percentage
      "com.apple.menuextra.battery" = {
        ShowPercent = "NO";
        ShowTime = "YES";
      };

      # Disable personalized advertising
      "com.apple.AdLib".allowApplePersonalizedAdvertising = false;
    };
  };
}
