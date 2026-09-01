{ config, lib, ... }:
let
  inherit (config.programs.browserPolicy.blocking) customFilterLists;
  inherit (config.programs.browserPolicy.blocking) ublock;
  toPairList =
    attrs:
    lib.pipe attrs [
      lib.attrsToList
      (map (nameValue: [
        nameValue.name
        nameValue.value
      ]))
    ];

in
{
  # Configure uBlock Origin via Zen Browser policies
  programs.zen-browser.policies."3rdparty".Extensions."uBlock0@raymondhill.net" = {
    adminSettings = {
      # Legacy (still supported) block to seed dynamic rules for medium mode
      dynamicFilteringString = ublock.dynamicFilteringRules;
    };

    userSettings = toPairList (ublock.userSettings // { importedLists = customFilterLists; });

    # Advanced Settings
    advancedSettings = toPairList ublock.advancedSettings;

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
