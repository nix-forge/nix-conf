{ lib, ... }: {
  options.programs.browserSuite.shared.ublock = {
    defaultFilterLists = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      internal = true;
      readOnly = true;
      default = [
        "user-filters"
        "ublock-filters"
        "ublock-badware"
        "ublock-privacy"
        "ublock-unbreak"
        "ublock-quick-fixes"
        "easylist"
        "easyprivacy"
        "urlhaus-1"
        "plowe-0"
      ];
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      internal = true;
      readOnly = true;
      default = {
        advancedUserEnabled = false;
        autoUpdate = true;
        cnameUncloakEnabled = true;
        dynamicFilteringEnabled = false;
        hyperlinkAuditingDisabled = true;
        prefetchingDisabled = true;
        suspendUntilListsAreLoaded = true;
      };
    };
  };
}
