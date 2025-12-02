{ callPackage, lib, ... }:

let
  dirPath = ./.;
  entries = builtins.readDir dirPath;
  packageDirs = lib.filterAttrs (
    dirName: type:
    type == "directory" && builtins.pathExists (dirPath + "/${dirName}/default.nix")
  ) entries;
  attrNameFor = dirName: lib.replaceStrings [ "_" ] [ "-" ] dirName;
in
lib.mapAttrs' (dirName: _: {
  name = attrNameFor dirName;
  value = callPackage (dirPath + "/${dirName}") { };
}) packageDirs
