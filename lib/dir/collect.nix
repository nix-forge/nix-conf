# Recursive directory tree collection
#
# Functions for recursively traversing directory trees and collecting
# files matching a suffix into nested attrsets
{ lib, ... }:
let
  inherit (builtins) readDir;
  inherit (lib)
    filterAttrs
    mapAttrs
    mapAttrs'
    nameValuePair
    removeSuffix
    hasSuffix
    ;

  # Recursively traverse a directory tree and collect files by suffix
  #
  # At each directory level:
  #   - Regular files matching the suffix are collected into an attrset
  #     under the given key, with the suffix stripped from their names
  #     and their values set to { file = <path>; }
  #   - Subdirectories are recursed into and become nested attrsets
  #   - The key attrset is only added if matching files exist at that level
  #
  # Type: String -> String -> Path -> AttrSet
  # Example:
  #   collectBySuffix ".age" "secrets" ./secrets/users
  #   # => {
  #   #   ianmh = {
  #   #     secrets = {
  #   #       gitconfig-userName = { file = ./secrets/users/ianmh/gitconfig-userName.age; };
  #   #       gitconfig-userEmail = { file = ./secrets/users/ianmh/gitconfig-userEmail.age; };
  #   #       ...
  #   #     };
  #   #   };
  #   # }
  collectBySuffix =
    paramName: suffix: key: path:
    let
      entries = readDir path;

      matchingFiles = filterAttrs (name: type: type == "regular" && hasSuffix suffix name) entries;

      subdirs = filterAttrs (_: type: type == "directory") entries;

      collected = mapAttrs' (
        name: _: nameValuePair (removeSuffix suffix name) { ${paramName} = path + "/${name}"; }
      ) matchingFiles;

      children = mapAttrs (name: _: collectBySuffix paramName suffix key (path + "/${name}")) subdirs;
    in
    (if collected != { } then { ${key} = collected; } else { }) // children;
in
{
  inherit collectBySuffix;
}
