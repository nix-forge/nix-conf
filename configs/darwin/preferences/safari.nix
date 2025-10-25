{
  system.defaults = {
    CustomUserPreferences = {
      "com.apple.Safari" = {
        # Include the Develop menu
        IncludeDevelopMenu = true;

        # Include the Internal Debug menu
        IncludeInternalDebugMenu = true;

        # Enable WebKit Developer Extras (right-click inspect element)
        WebKitDeveloperExtrasEnabledPreferenceKey = true;

        # Enable WebKit Developer Extras (alternative key)
        "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" = true;

        # Disable universal search for privacy
        UniversalSearchEnabled = false;

        # Suppress search suggestions for privacy
        SuppressSearchSuggestions = true;

        # Don't open "safe" downloads automatically
        AutoOpenSafeDownloads = false;

        # Disable snapshot cache for History and Top Sites
        DebugSnapshotsUpdatePolicy = 2;

        # Make Safari's search banners default to Contains instead of Starts With
        FindOnPageMatchesWordStartsOnly = false;

        # Remove useless icons from Safari's bookmarks bar
        ProxiesInBookmarksBar = "()";
      };
    };
  };
}
