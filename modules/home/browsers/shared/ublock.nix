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
        "ublock-abuse"
        "ublock-unbreak"
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
        autoUpdate = true;
        cnameUncloakEnabled = true;
        hyperlinkAuditingDisabled = true;
        prefetchingDisabled = true;
      };
    };
  };
}
