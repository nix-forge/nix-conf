# Directory utility library for Nix configurations
#
# This module provides functions for working with directories in Nix,
# including reading directory contents, filtering entries, and importing modules.
#
# Auto-imports all .nix files in this directory and merges their exports.
{ lib }:
let
  inherit (builtins) readDir attrNames foldl';
  inherit (lib) hasSuffix filterAttrs;

  # Get all .nix files except default.nix
  entries = readDir ./.;
  nixFiles = attrNames (filterAttrs (name: type:
    type == "regular" &&
    hasSuffix ".nix" name &&
    name != "default.nix"
  ) entries);

  # Load order determines dependency availability
  # Each module receives all previously loaded functions as arguments
  loadOrder = [ "entry.nix" "read.nix" "filter.nix" "utils.nix" "import.nix" ];

  # Only load files that exist and are in our load order
  filesToLoad = builtins.filter (f: builtins.elem f nixFiles) loadOrder;

  # Load modules in order, accumulating exports
  # Each module gets lib + all previously exported functions
  loaded = foldl' (acc: fileName:
    let
      module = import (./. + "/${fileName}") (acc // { inherit lib; });
    in
    acc // module
  ) {} filesToLoad;

in
loaded // {
  # Convenient aliases
  read = loaded.readEntries;
  nixEntries = loaded.readNixEntries;
}
