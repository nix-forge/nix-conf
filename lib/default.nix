# Auto-import all lib modules from subdirectories
#
# Automatically discovers and loads all .nix files from subdirectories.
# Uses iterative loading until all dependencies are resolved.
#
# Structure:
#   lib/
#   ├── default.nix     <- This file
#   └── dir/
#       ├── entry.nix   <- { lib, ... }: { mkEntry = ...; }
#       └── read.nix    <- { lib, mkEntry, ... }: { readEntries = ...; }
#
# Each .nix file should:
#   1. Accept { lib, ... }: as arguments (use ... to accept other deps)
#   2. Return an attrset of functions to export
#
# Result: { dir = { mkEntry, readEntries, ... }; }
{ lib }:
let
  inherit (builtins) readDir attrNames pathExists foldl';
  inherit (lib) hasSuffix filterAttrs;

  # Get all subdirectories
  entries = readDir ./.;
  subdirs = attrNames (filterAttrs (_: type: type == "directory") entries);

  # Get .nix files from a directory (excluding default.nix)
  getNixFiles = dir:
    let
      dirEntries = if pathExists dir then readDir dir else {};
    in
    attrNames (filterAttrs (name: type:
      type == "regular" &&
      hasSuffix ".nix" name &&
      name != "default.nix"
    ) dirEntries);

  # Load all modules once with given deps, collecting successful exports
  loadPass = subdirPath: nixFiles: deps:
    foldl' (acc: fileName:
      let
        tryImport = builtins.tryEval (import (subdirPath + "/${fileName}") (deps // { inherit lib; }));
      in
      if tryImport.success then acc // tryImport.value else acc
    ) {} nixFiles;

  # Load a subdirectory with multiple passes for dependency resolution
  loadSubdir = name:
    let
      subdirPath = ./. + "/${name}";
      nixFiles = getNixFiles subdirPath;

      # Run enough passes to resolve all dependencies (max = number of files)
      # Each pass adds more resolved modules to deps
      finalDeps = foldl' (deps: _:
        loadPass subdirPath nixFiles deps
      ) {} nixFiles;
    in
    if nixFiles == [] then {} else finalDeps;

  # Check if a subdirectory has any .nix files
  hasNixFiles = name: (getNixFiles (./. + "/${name}")) != [];

  # Build the final attrset of all subdirectories
  result = foldl' (acc: name:
    if hasNixFiles name then
      acc // { ${name} = loadSubdir name; }
    else
      acc
  ) {} subdirs;

in
result
