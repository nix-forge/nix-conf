{ lib, ... }:
let
  toPairList =
    attrs:
    lib.mapAttrsToList (name: value: [
      name
      (if builtins.isBool value then lib.boolToString value else toString value)
    ]) attrs;
in
{
  ublock.mkPolicy =
    {
      settings,
      defaultFilterLists,
      customFilterLists ? [ ],
    }:
    {
      userSettings = toPairList settings;
    }
    // lib.optionalAttrs (customFilterLists != [ ]) {
      toOverwrite = {
        filters = [ ];
        filterLists = defaultFilterLists ++ customFilterLists;
      };
    };
}
