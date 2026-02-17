# Core directory entry creation
#
# Creates a structured record for a file or directory with metadata
# This is the foundation that all other dir functions build upon
{ lib, ... }:
let
  inherit (builtins) readDir pathExists;
  inherit (lib)
    mapAttrsToList
    hasSuffix
    hasPrefix
    pathIsRegularFile
    ;

  # Type: Path -> String -> String -> Entry
  # Entry = {
  #   name: String,        # Original name (e.g., "foo.nix" or "bar")
  #   type: String,        # File type from readDir: "regular", "directory", "symlink", "unknown"
  #   path: Path,          # Full path to the entry
  #   baseName: String,    # Same as name (for consistency)
  #   isFile: Bool,        # True if regular file
  #   isDir: Bool,         # True if directory
  #   isLink: Bool,        # True if symlink
  #   isHidden: Bool,      # True if name starts with "."
  #   isNixFile: Bool,     # True if .nix file
  #   isDefault: Bool,     # True if file is "default.nix"
  #   hasDefault: Bool,    # True if directory contains default.nix
  #   hasNixFiles: Bool,   # True if directory contains any .nix files (recursive)
  #   isNix: Bool,         # True if importable (.nix file or dir with nix files)
  #   extension: String?,  # File extension including dot, or null
  # }
  mkEntry =
    parentPath: name: type:
    let
      self =
        parentPath: name: type:
        let
          path = parentPath + "/${name}";

          # Basic type checks
          isFile = type == "regular";
          isDir = type == "directory";
          isLink = type == "symlink";
          isHidden = hasPrefix "." name;

          # Nix-specific checks
          isNixFile = isFile && hasSuffix ".nix" name;
          isDefault = name == "default.nix";
          hasDefault = isDir && pathIsRegularFile (path + "/default.nix");

          # Recursive check for nix files in directory
          hasNixFiles =
            if !(isDir && pathExists path) then
              false
            else
              let
                children = mapAttrsToList (self path) (readDir path);
              in
              builtins.any (e: e.isNixFile || (e.isDir && e.hasNixFiles)) children;

          # Can this entry be imported as a Nix module?
          isNix = !isHidden && (isNixFile || hasNixFiles);

          # Extract extension
          extMatch = builtins.match ".*(\\..[^.]*)" name;
          extension = if extMatch != null then builtins.elemAt extMatch 0 else null;
        in
        {
          inherit
            name
            type
            path
            isFile
            isDir
            isLink
            isHidden
            ;
          inherit
            isNixFile
            isDefault
            hasDefault
            hasNixFiles
            isNix
            extension
            ;
          baseName = name;
        };
    in
    self parentPath name type;
in
{
  inherit mkEntry;
}
