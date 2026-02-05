{
  system.defaults = {
    CustomUserPreferences = {
      "com.apple.SoftwareUpdate" = {
        # Enable the automatic update check
        AutomaticCheckEnabled = true;

        # Check for software updates daily (frequency: 1 = daily)
        ScheduleFrequency = 1;

        # Automatically download newly available updates in background
        AutomaticDownload = 1;

        # Install System data files & security updates
        CriticalUpdateInstall = 1;
      };
    };
  };
}
