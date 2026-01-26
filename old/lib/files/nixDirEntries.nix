{ lib, ... }:
dir: filter_fn: val_fn:
let
  inherit (import ./default.nix { inherit lib; }) mkDirEntries;
  filter = entry: (entry.isNixFile || entry.hasNixFiles) && filter_fn entry;
  mapListToAttrs = fn: attrsList: builtins.listToAttrs (map fn attrsList);
  removePostfix =
    entry:
    if entry.isNixFile then lib.removeSuffix ".nix" entry.name else entry.name;
in
lib.pipe dir [
  # creates a list of directory entries for each file in the directory
  mkDirEntries
  # filter out entries that are not nix files or directories with nix files
  (builtins.filter filter)
  # convert the list to AttrSet
  (mapListToAttrs (entry: {
    # remove .nix from nix files else keep directory name
    name = removePostfix entry;
    # set the value to the result of the val_fn with the entry
    value = val_fn entry;
  }))
]
