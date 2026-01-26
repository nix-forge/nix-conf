{
  system.defaults = {
    CustomUserPreferences = {
      # Mail settings
      "com.apple.Mail" = {
        # Copy email addresses as plain email instead of "Name <email>"
        AddressesIncludeNameOnPasteboard = false;
      };

      # iTunes/Music settings
      "com.apple.iTunes" = {
        # Disable the Ping sidebar
        disablePingSidebar = true;
        # Disable all Ping functionality
        disablePing = true;
        # Make ⌘ + F focus the search input
        NSUserKeyEquivalents = {
          "Target Search Field" = "@F";
        };
      };

      # Terminal settings
      "com.apple.terminal" = {
        # Only use UTF-8 encoding
        StringEncodings = 4;
      };
    };
  };
}
