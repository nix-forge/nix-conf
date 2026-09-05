_:
let
  personalPolicies = {
    AutofillAddressEnabled = false;
    AutofillCreditCardEnabled = false;
    DisplayBookmarksToolbar = "newtab";
    PasswordManagerEnabled = false;
    SearchSuggestEnabled = false;
    FirefoxHome = {
      Search = true;
      TopSites = true;
      Highlights = true;
      Pocket = false;
      Snippets = false;
    };
    FirefoxSuggest = {
      WebSuggestions = false;
    };
  };

  personalSettings = {
    "browser.startup.homepage" = "about:home";
    "browser.startup.homepage_override.mstone" = "ignore";
    "browser.startup.page" = 3;
    "browser.newtabpage.enabled" = true;
    "browser.download.always_ask_before_handling_new_types" = false;
    "browser.download.start_downloads_in_tmp_dir" = false;
    "browser.urlbar.suggest.searches" = false;
    "browser.urlbar.trimHttps" = false;
  };

in
{
  programs.browserSuite = {
    defaultBrowser = "zen";
    scrolling = "natural";
  };

  programs.firefox = {
    policies = personalPolicies;
    profiles.default = {
      name = "Personal";
      settings = personalSettings;
    };
  };

  programs.zen-browser = {
    policies = personalPolicies;
    profiles.default.settings = personalSettings;
  };
}
