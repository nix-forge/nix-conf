# Auto-import all lib modules from subdirectories recursively
#
# Automatically discovers and loads all .nix files from subdirectories.
# Uses lazy evaluation with fixed-point to resolve dependencies.
# No default.nix files are needed in subdirectories.
#
# Structure:
#   lib/
#   ├── default.nix     <- This file (only default.nix in lib)
#   └── dir/
#       ├── entry.nix   <- { lib, ... }: { mkEntry = ...; }
#       └── read.nix    <- { lib, mkEntry, ... }: { readEntries = ...; }
#       └── subdir/
#           └── foo.nix <- { lib, mkEntry, ... }: { foo = ...; }
#
# Each .nix file should:
#   1. Accept { lib, ... }: as arguments (use ... to accept other deps)
#   2. Return an attrset of functions to export
#
# Result: { dir = { mkEntry, readEntries, subdir = { foo, ... }, ... }; }
{ lib }:
let
  inherit (builtins)
    readDir
    attrNames
    pathExists
    foldl'
    ;
  inherit (lib)
    hasSuffix
    filterAttrs
    hasPrefix
    fix
    ;

  # Get entries from a directory
  getEntries = dir: if pathExists dir then readDir dir else { };

  # Get .nix files from a directory (excluding default.nix and hidden files)
  getNixFiles =
    dir:
    attrNames (
      filterAttrs (
        name: type:
        type == "regular" && hasSuffix ".nix" name && name != "default.nix" && !(hasPrefix "." name)
      ) (getEntries dir)
    );

  # Get subdirectories from a directory (excluding hidden dirs)
  getSubdirs =
    dir:
    attrNames (filterAttrs (name: type: type == "directory" && !(hasPrefix "." name)) (getEntries dir));

  # Load a directory using fixed-point for lazy dependency resolution
  # All files in the directory get access to all exports via 'self'
  loadDirFiles =
    dirPath: nixFiles:
    let
      # Import each file lazily, passing self (which will contain all exports)
      importFile = self: fileName: import (dirPath + "/${fileName}") { inherit lib self; };

      # Use fix with a lazy merge using lib.foldr (not foldl')
      # foldr is lazy in the accumulator, allowing the fixed-point to work
      result = fix (self: lib.foldr (fileName: acc: (importFile self fileName) // acc) { } nixFiles);
    in
    result;

  # Recursively load a directory tree
  # Returns an attrset with:
  #   - All functions exported by .nix files in this directory
  #   - Nested attrsets for each subdirectory
  loadDirRecursive =
    dirPath:
    let
      nixFiles = getNixFiles dirPath;
      subdirs = getSubdirs dirPath;

      # Load all .nix files in this directory with lazy deps
      fileExports = if nixFiles == [ ] then { } else loadDirFiles dirPath nixFiles;

      # Recursively load subdirectories
      subdirExports = foldl' (
        acc: subdirName:
        let
          subdirPath = dirPath + "/${subdirName}";
          subdirResult = loadDirRecursive subdirPath;
        in
        # Only add subdirectory if it has any exports
        if subdirResult == { } then acc else acc // { ${subdirName} = subdirResult; }
      ) { } subdirs;
    in
    fileExports // subdirExports;

  # Get all top-level subdirectories of lib/
  topLevelSubdirs = getSubdirs ./.;

  # Build the final attrset of all subdirectories
  result = foldl' (
    acc: name:
    let
      subdirPath = ./. + "/${name}";
      subdirResult = loadDirRecursive subdirPath;
    in
    if subdirResult == { } then acc else acc // { ${name} = subdirResult; }
  ) { } topLevelSubdirs;

in
result
