{
  programs.firefox.policies = {
    DisplayBookmarksToolbar = "never";
    DisableFirefoxAccounts = true;
    PasswordManagerEnabled = false;
    DisablePocket = true;
    DisableTelemetry = true;
    HardwareAcceleration = true;
    DisableFirefoxStudies = true;
    DisableFirefoxScreenshots = true;
    NoDefaultBookmarks = true;
    SearchSuggestEnabled = false;
    DisableFormHistory = true;
    DontCheckDefaultBrowser = true;
    FirefoxHome = {
      Search = true;
      TopSites = false;
      SponsoredTopSites = false;
      Highlights = false;
      Pocket = false;
      SponsoredPocket = false;
      Snippets = false;
      Locked = true;
    };
    UserMessaging = {
      WhatsNew = false;
      ExtensionRecommendations = false;
      SkipOnboarding = true;
      MoreFromMozilla = false;
      Locked = true;
    };
    FirefoxSuggest = {
      WebSuggestions = false;
      SponsoredSuggestions = false;
      ImproveSuggest = false;
      Locked = true;
    };
    ExtensionUpdate = true;
  };
}
