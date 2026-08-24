{ lib, ... }:
let
  inherit (import ../../shared/ublock-filter-lists.nix) customFilterLists;
  toPairList =
    attrs:
    lib.pipe attrs [
      lib.attrsToList
      (map (nameValue: [
        nameValue.name
        nameValue.value
      ]))
    ];

  # uBO medium mode (global) dynamic rules
  mediumModeRules = ''
    * * 3p-script block
    * * 3p-frame block
  '';
  captchaAllowRules = ''
    * challenges.cloudflare.com * noop
    * www.google.com * noop
    * www.gstatic.com * noop
    * hcaptcha.com * noop
    * recaptcha.net * noop
  '';
  commonFixesRules = ''
    * youtube.com * 3p-script noop

    github.com * 3p-script noop
    github.com * 3p-frame noop

    www.reddit.com * 3p-script noop
    www.reddit.com * 3p-frame noop

    edstem.org * 3p-script noop
    edstem.org * 3p-frame noop

    accounts.google.com * 3p-script noop

    chatgpt.com * 3p-script noop
    chatgpt.com * 3p-frame noop

    home-manager-options.extranix.com * 3p-script noop

    www.instagram.com * 3p-script noop
    www.instagram.com * 3p-frame noop

    x.com * 3p-frame noop
    x.com * 3p-script noop

    www.linkedin.com * 3p-script noop
    www.linkedin.com * 3p-frame noop

    www.doordash.com * 3p-script noop
    www.doordash.com * 3p-frame noop

    www.gradescope.com * 3p-frame noop
    www.gradescope.com * 3p-script noop

    myworkdayjobs.com * 3p-script noop
    myworkdayjobs.com * 3p-frame noop

    www.instacart.com * 3p-script noop
    www.instacart.com * 3p-frame noop

    grammarly.com * 3p-script noop
    grammarly.com * 3p-frame noop

    canvas.cornell.edu * 3p-script noop
    canvas.cornell.edu * 3p-frame noop

    cornell.app.box.com * 3p-frame noop
    cornell.app.box.com * 3p-script noop

    pcpartpicker.com * 3p-frame noop
    pcpartpicker.com * 3p-script noop

    gemini.google.com * 3p-frame noop
    gemini.google.com * 3p-script noop

    digital.fidelity.com * 3p-frame noop
    digital.fidelity.com * 3p-script noop
  '';

  customRules = lib.concatStrings [
    mediumModeRules
    captchaAllowRules
    commonFixesRules
  ];
in
{
  # Configure uBlock Origin via Zen Browser policies
  programs.zen-browser.policies."3rdparty".Extensions."uBlock0@raymondhill.net" = {
    adminSettings = {
      # Legacy (still supported) block to seed dynamic rules for medium mode
      dynamicFilteringString = customRules;
    };

    userSettings = toPairList {
      # Privacy settings
      prefetchingDisabled = true;
      hyperlinkAuditingDisabled = true;
      cnameUncloakEnabled = true;

      # Filter list settings
      autoUpdate = true;
      advancedUserEnabled = true;
      dynamicFilteringEnabled = true;

      # Imported custom filter lists
      importedLists = customFilterLists;
    };

    # Advanced Settings
    advancedSettings = toPairList {
      autoUpdateDelayAfterLaunch = 10;
      updateAssetBypassBrowserCache = true;
      filterAuthorMode = true;
    };

    toOverwrite = {
      # The array of strings that represent all the lines making the text to use for "My Filters" which is the user-filters
      filters = [ ];

      filterLists = [
        # My Filters
        "user-filters"

        # Built-in
        "ublock-filters"
        "ublock-badware"
        "ublock-privacy"
        "ublock-quick-fixes"
        "ublock-unbreak"
        # "ublock-experimental"

        # Ads
        "easylist"
        "adguard-mobile"

        # Privacy
        "easyprivacy"
        "adguard-spyware-url"
        "block-lan"

        # Malware protection, security
        "urlhaus-1"

        # Multipurpose
        "plowe-0"
        "dpollock-0"

        # Cookie notices
        "fanboy-cookiemonster"

        # Social Widgets
        "fanboy-social"

        # Annoyances
        "easylist-chat"
        "easylist-newsletters"
        "easylist-notifications"
        "easylist-annoyances"
        "ublock-annoyances"
      ]
      ++ customFilterLists;
    };
  };
}
