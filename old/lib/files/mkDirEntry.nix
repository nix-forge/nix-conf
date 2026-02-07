{ lib, ... }:
dirName: name: type:
let
  inherit (import ./default.nix { inherit lib; }) mkDirEntry;
  _atRoot = path: builtins.match "^/[^/]*/?$" path != null;
  _hasPrefix = lib.hasPrefix (toString dirName) name;
  _extMatch = builtins.match "^.*(\\..+)$" name;
in
rec {
  inherit name type;
  path = "${pathPrefix}/${baseName}";
  exists = builtins.pathExists path;
  baseName = baseNameOf name;
  pathPrefix = toString dirName;
  relPath = if _hasPrefix then lib.removePrefix pathPrefix name else name;
  atRoot = _atRoot relPath;
  extension = if _extMatch != null then builtins.elemAt _extMatch 0 else null;
  isHidden = lib.hasPrefix "." baseName;
  isLink = type == "symlink";
  isFile = type == "regular";
  isDir = type == "directory";
  isProject = !isHidden && (isFile || isDir);
  isNixFile = isFile && lib.hasSuffix ".nix" baseName;
  isDefault = isFile && baseName == "default.nix";
  hasDefault = isDir && lib.pathIsRegularFile "${path}/default.nix";
  hasNixFiles =
    let
      ls = lib.mapAttrsToList (mkDirEntry path) (builtins.readDir path);
    in
    exists && isDir && (builtins.any (it: it.isNixFile || (it.isDir && it.hasNixFiles)) ls);
  isNix = isProject && (isNixFile || (isDir && hasNixFiles));
}
