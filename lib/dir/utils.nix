# Low-level import utilities
#
# Helper functions for converting entries to imported values
{ lib, ... }:
let
  inherit (lib) removeSuffix;
in
rec {
  # Remove .nix suffix from a filename for use as attribute name
  #
  # Type: Entry -> String
  entryAttrName = entry:
    if entry.isNixFile then removeSuffix ".nix" entry.name else entry.name;

  # Convert an entry to an imported module
  #
  # Type: Entry -> a
  importEntry = entry: import entry.path;

  # Convert a list of entries to an attrset with imported values
  #
  # Type: [Entry] -> AttrSet
  entriesToAttrs = entries:
    builtins.listToAttrs (map (e: {
      name = entryAttrName e;
      value = importEntry e;
    }) entries);
}
