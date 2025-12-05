{ pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
in
{
  programs.firefox.policies = {
    AppAutoUpdate = false;
    ManualAppUpdateOnly = true;
    DisableFeedbackCommands = true;
    DisableSetDesktopBackground = true;
    DisableDefaultBrowserAgent = true;
    DisableDeveloperTools = false;
    DisableProfileRefresh = true;
    DisableProfileImport = true;
    DisablePrivateBrowsing = false;
    DisplayBookmarksToolbar = "never";
    DisableFirefoxAccounts = true;
    PasswordManagerEnabled = false;
    AutofillAddressEnabled = false;
    AutofillCreditCardEnabled = false;
    DisableMasterPasswordCreation = true;
    DisablePasswordReveal = true;
    DisablePocket = true;
    DisableTelemetry = true;
    HardwareAcceleration = true;
    DisableFirefoxStudies = true;
    DisableFirefoxScreenshots = false;
    NoDefaultBookmarks = true;
    SearchSuggestEnabled = false;
    DisableFormHistory = true;
    DontCheckDefaultBrowser = true;
    SkipTermsOfUse = true;
    HttpsOnlyMode = "force_enabled";
    EnterprisePoliciesEnabled = isDarwin;
    FirefoxHome = {
      Search = true;
      SponsoredTopSites = false;
      SponsoredPocket = false;
      SponsoredStories = false;
      Highlights = false;
      Pocket = false;
      Snippets = false;
      Locked = true;
    };
    UserMessaging = {
      WhatsNew = false;
      ExtensionRecommendations = false;
      FeatureRecommendations = false;
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
