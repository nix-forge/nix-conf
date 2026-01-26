{
  system.defaults = {
    NSGlobalDomain = {
      # Disable press-and-hold for keys in favor of key repeat
      ApplePressAndHoldEnabled = false;

      # Set a fast keyboard repeat rate (1-120, where lower is faster)
      KeyRepeat = 2;

      # Set a shorter delay before key repeat (10-120, where lower is faster)
      InitialKeyRepeat = 20;

      # Text input & typing corrections
      # Disable automatic capitalization
      NSAutomaticCapitalizationEnabled = false;

      # Disable automatic period substitution (smart stops)
      NSAutomaticPeriodSubstitutionEnabled = false;

      # Disable automatic dash substitution (smart dashes)
      NSAutomaticDashSubstitutionEnabled = false;

      # Disable automatic quote substitution (smart quotes)
      NSAutomaticQuoteSubstitutionEnabled = false;

      # Disable automatic spelling correction (auto-correct)
      NSAutomaticSpellingCorrectionEnabled = false;
    };
  };
}
