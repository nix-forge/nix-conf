{
  targets.darwin.defaults = {
    "com.apple.Mail".AddressesIncludeNameOnPasteboard = false;

    "com.apple.iTunes" = {
      disablePingSidebar = true;
      disablePing = true;
      NSUserKeyEquivalents = {
        "Target Search Field" = "@F";
      };
    };

    "com.apple.terminal".StringEncodings = 4;
  };
}
