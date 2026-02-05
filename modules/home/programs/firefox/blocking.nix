{ lib, ... }:
let
  toPairList =
    attrs:
    lib.pipe attrs [
      lib.attrsToList
      (builtins.map (nameValue: [
        nameValue.name
        nameValue.value
      ]))
    ];

  # Privacy filters
  privacyEssentials = "https://raw.githubusercontent.com/yokoffing/filterlists/main/privacy_essentials.txt";
  click2Load = "https://raw.githubusercontent.com/yokoffing/filterlists/main/click2load.txt";
  haegeziProMini = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.mini.txt";
  legitUrlShortener = "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/LegitimateURLShortener.txt";
  clearUrlsUbo = "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/ClearURLs%20for%20uBo/clear_urls_uboified.txt";
  thirdPartyFonts = "https://raw.githubusercontent.com/yokoffing/filterlists/main/block_third_party_fonts.txt";

  # Annoyances filters
  yokoffingAnnoyances = "https://raw.githubusercontent.com/yokoffing/filterlists/main/annoyance_list.txt";
  browseWithoutLogin = "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/BrowseWebsitesWithoutLoggingIn.txt";
  youTubeClearView = "https://raw.githubusercontent.com/yokoffing/filterlists/main/youtube_clear_view.txt";
  bypassPaywallsClean = "https://gitflic.ru/project/magnolia1234/bypass-paywalls-clean-filters/blob/raw?file=bpc-paywall-filter.txt";
  antiPaywall = "https://raw.githubusercontent.com/liamengland1/miscfilters/master/antipaywall.txt";

  # Security filters
  mostAbusedTlds = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/spam-tlds-ublock.txt";
  dandelionAntiMalware = "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/Dandelion%20Sprout's%20Anti-Malware%20List.txt";
  maliciousWebsiteBlocklist = "https://raw.githubusercontent.com/iam-py-test/my_filters_001/main/antimalware.txt";

  # All-purpose combo lists
  ublockComboList = "https://raw.githubusercontent.com/iam-py-test/uBlock-combo/main/list.txt";
  haegeziComboAltMini = "https://raw.githubusercontent.com/cbuijs/hagezi/refs/heads/main/combo/alt-suggested-mini/domains.top-n.adblock";

  # Extra optional filter lists
  youTubeShorts = "https://raw.githubusercontent.com/gijsdev/ublock-hide-yt-shorts/master/list.txt";

  # Create a nix list of all custom lists
  customFilterLists = [
    # Privacy filters
    privacyEssentials
    click2Load
    haegeziProMini
    legitUrlShortener
    clearUrlsUbo
    thirdPartyFonts

    # Annoyances filters
    yokoffingAnnoyances
    browseWithoutLogin
    youTubeClearView
    bypassPaywallsClean
    antiPaywall

    # Security filters
    mostAbusedTlds
    dandelionAntiMalware
    maliciousWebsiteBlocklist

    # All-purpose combo lists
    ublockComboList
    haegeziComboAltMini

    # Optional extra lists
    youTubeShorts
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
    www.reddit.com * 3p-script noop
    edstem.org * 3p-script noop
    accounts.google.com * 3p-script noop
    chatgpt.com * 3p-script noop
    home-manager-options.extranix.com * 3p-script noop
    www.instagram.com * 3p-script noop
    www.linkedin.com * 3p-script noop
    www.doordash.com * 3p-script noop
    www.gradescope.com * 3p-frame noop
    myworkdayjobs.com * 3p-script noop
    www.instacart.com * 3p-script noop
  '';

  customRules = lib.concatStrings [
    mediumModeRules
    captchaAllowRules
    commonFixesRules
  ];
in
{
  # Configure uBlock Origin via Firefox policies
  programs.firefox.policies."3rdparty".Extensions."uBlock0@raymondhill.net" = {
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
        "ublock-experimental"

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
