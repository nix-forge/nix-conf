# Directory reading functions
#
# Functions for reading directory contents and returning entry records
{ lib, self, ... }:
let
  inherit (builtins) readDir filter;
  inherit (lib) mapAttrsToList;
  inherit (self) mkEntry;
in
rec {
  # Read a directory and return a list of entry records
  #
  # Type: Path -> [Entry]
  readEntries = path: mapAttrsToList (mkEntry path) (readDir path);

  # Read entries with a predicate filter
  #
  # Type: (Entry -> Bool) -> Path -> [Entry]
  readEntriesWhere = pred: path: filter pred (readEntries path);

  # Read only nix-importable entries (files/dirs with .nix content)
  #
  # Type: Path -> [Entry]
  readNixEntries = readEntriesWhere (e: e.isNix);
}
