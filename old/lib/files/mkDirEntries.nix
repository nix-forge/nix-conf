{ lib, ... }:
dir:
let
  inherit (import ./default.nix { inherit lib; }) mkDirEntry;
  map = mkDirEntry dir; # creates a functions with name: and type: as parameters
  data = builtins.readDir dir; # creates the map needed for the mapAttrs to list function
  entryList = lib.mapAttrsToList map data; # creates a list of directory entries for each file in the directory
in
entryList
