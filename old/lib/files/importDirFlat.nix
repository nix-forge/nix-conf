{ lib, ... }:
/*
  Flattens a directory tree of nix modules into a single-level
  attrset whose keys are the path segments joined by a separator
  (default: "-").

  Example:
    dir
    ├─ hardware/
    │  └─ gpu/
    │     └─ nvidia.nix
    └─ networking/
       ├─ default.nix
       └─ firewall/
          └─ default.nix

  becomes
    {
      hardware-gpu-nvidia = import ./dir/hardware/gpu/nvidia.nix;
      networking = import ./dir/networking;              # default.nix
      networking-firewall = import ./dir/networking/firewall; # default.nix
    }

  Notes:
  - If a directory has a default.nix, it is included as a key at its level,
    and we still recurse into its subdirectories.
  - `default.nix` files are not added as leaf entries directly to avoid duplicates;
    the directory’s own key represents them.
*/
dir:
{
  # Names to exclude (by base name), e.g. ["README.md"]
  filter ? [ ],
  # Optional custom filter function over entries
  filter_fn ? ({ name, isNix, ... }: isNix && !(builtins.elem name filter)),
  # Whether to import a directory when it has a default.nix
  importDirDefault ? true,
  # Key separator
  sep ? "-",
}:
let
  inherit (import ./default.nix { inherit lib; }) mkDirEntries;

  # Returns list of entries for a given path
  entriesOf = path: builtins.filter filter_fn (mkDirEntries path);

  # Build a flat attrset from a directory with a given prefix path (list of segments)
  go =
    path: prefix:
    let
      entries = entriesOf path;

      # Include the directory's default.nix as a key if present
      selfEntry =
        if importDirDefault && lib.pathIsRegularFile "${path}/default.nix" then
          [
            {
              name = lib.concatStringsSep sep prefix;
              value = import path;
            }
          ]
        else
          [ ];

      # Recurse into children and include leaf nix files (non-default)
      children = lib.concatMap (
        entry:
        if entry.isDir && entry.hasNixFiles then
          # Recurse into subdir; extend prefix with dir name
          let
            nextPrefix = prefix ++ [ entry.name ];
          in
          lib.attrsToList (go entry.path nextPrefix)
        else if entry.isNixFile && entry.baseName != "default.nix" then
          # Leaf nix file: use file base name (without .nix)
          let
            base = lib.removeSuffix ".nix" entry.name;
            key = lib.concatStringsSep sep (prefix ++ [ base ]);
          in
          [
            {
              name = key;
              value = import entry.path;
            }
          ]
        else
          [ ]
      ) entries;

    in
    builtins.listToAttrs (selfEntry ++ children);
in
# Start at root, with initial prefix equal to the root directory name
# so that a default.nix at the root becomes that top-level key.
# For nixosModules/homeModules use-cases, the root typically
# doesn’t have a default.nix, so this mainly affects subtrees.
go dir [ ]
