# TODO: move this config to firefox policies instead of managed storage
{ lib, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  toPairList =
    attrs:
    lib.pipe attrs [
      lib.attrsToList
      (builtins.map (nameValue: [
        nameValue.name
        nameValue.value
      ]))
    ];

  # Where Firefox reads Managed Storage manifests (per-user)
  # macOS:  ~/Library/Application Support/Mozilla/ManagedStorage/
  # Linux:  ~/.mozilla/managed-storage/
  managedStoragePath =
    if isDarwin then
      "Library/Application Support/Mozilla/ManagedStorage"
    else
      ".mozilla/managed-storage";

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
  commonFixes = ''
    github.com * 3p-script noop
    www.reddit.com * 3p-script noop
    edstem.org * 3p-script noop
    accounts.riseworks.io * 3p-script noop
    accounts.google.com * 3p-script noop
    sofi.com * 3p-script noop
    chatgpt.com * 3p-script noop
    home-manager-options.extranix.com * 3p-script noop
  '';

  # High quality base filter lists URLs
  legitUrlShortener = "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/LegitimateURLShortener.txt";
  thirdPartyFonts = "https://raw.githubusercontent.com/yokoffing/filterlists/main/block_third_party_fonts.txt";
  click2Load = "https://raw.githubusercontent.com/yokoffing/filterlists/main/click2load.txt";

  # Extra Optional filter lists
  youTubeShorts = "https://raw.githubusercontent.com/gijsdev/ublock-hide-yt-shorts/master/list.txt";
in
{
  # Provision uBlock Origin Enterprise (Managed Storage) config for Firefox
  home.file."${managedStoragePath}/uBlock0@raymondhill.net.json".text = builtins.toJSON {
    name = "uBlock0@raymondhill.net";
    description = "_";
    type = "storage";
    data = {
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

          # Custom
          # High quality additional lists
          legitUrlShortener
          thirdPartyFonts
          click2Load

          # Optional Extra lists
          youTubeShorts
        ];
      };

      # User settings
      userSettings = toPairList {
        # Privacy
        prefetchingDisabled = true;
        hyperlinkAuditingDisabled = true;
        cnameUncloakEnabled = true;

        # Filter lists
        autoUpdate = true;

        advancedUserEnabled = true;
        dynamicFilteringEnabled = true;

        # Advanced Settings
        autoUpdateDelayAfterLaunch = 10;
        updateAssetBypassBrowserCache = true;

        importedLists = [
          legitUrlShortener
          thirdPartyFonts
          click2Load
          youTubeShorts
        ];
      };

      # Legacy (still supported) block to seed dynamic rules for medium mode.
      adminSettings = {
        dynamicFilteringString = lib.concatStrings [
          mediumModeRules
          captchaAllowRules
          commonFixes
        ];
      };
    };
  };
}
