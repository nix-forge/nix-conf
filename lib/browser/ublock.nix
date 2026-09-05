{ lib, ... }:
let
  toPairList =
    attrs:
    map (
      name:
      let
        value = attrs.${name};
      in
      [
        name
        (if builtins.isBool value then lib.boolToString value else toString value)
      ]
    ) (builtins.attrNames attrs);
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
