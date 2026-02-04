# High-level import functions
#
# Functions for importing directory trees in various ways
{ lib, self, ... }:
let
  inherit (builtins) concatLists listToAttrs;
  inherit (lib) concatStringsSep;
  inherit (self) readEntriesWhere allOf excludeNames entryAttrName importEntry entriesToAttrs;
in
rec {
  # Import all nix modules from a directory as an attrset (non-recursive)
  # Directories are imported if they have a default.nix, otherwise ignored
  #
  # Type: Path -> { exclude?: [String], filter?: Entry -> Bool } -> AttrSet
  # Example:
  #   importNix ./modules { exclude = [ "deprecated.nix" ]; }
  #   # => { foo = <contents of foo.nix>; bar = <contents of bar/default.nix>; }
  importNix = path: { exclude ? [], filter ? (_: true) }:
    let
      pred = allOf [
        (e: e.isNix)
        (excludeNames exclude)
        filter
        # Only include dirs that have default.nix (can be imported directly)
        (e: e.isNixFile || e.hasDefault)
      ];
    in
    entriesToAttrs (readEntriesWhere pred path);

  # Recursively import a directory tree into a nested attrset
  # Each directory becomes a nested attrset, each .nix file becomes a leaf
  #
  # Type: Path -> { exclude?: [String], filter?: Entry -> Bool } -> AttrSet
  # Example:
  #   importNixRecursive ./modules { }
  #   # => { hardware = { gpu = { nvidia = <...>; }; }; networking = <...>; }
  importNixRecursive = path: { exclude ? [], filter ? (_: true) }:
    let
      pred = allOf [ (e: e.isNix) (excludeNames exclude) filter ];

      processEntry = entry:
        if entry.isNixFile then
          importEntry entry
        else if entry.hasDefault then
          importEntry entry
        else
          importNixRecursive entry.path { inherit exclude filter; };

      entries = readEntriesWhere pred path;
    in
    listToAttrs (map (e: {
      name = entryAttrName e;
      value = processEntry e;
    }) entries);

  # Flatten a directory tree into a single-level attrset with path-based keys
  # Useful for module systems that need flat namespaces
  #
  # Type: Path -> { exclude?: [String], filter?: Entry -> Bool, sep?: String } -> AttrSet
  # Example:
  #   importFlat ./modules { sep = "-"; }
  #   # => { "hardware-gpu-nvidia" = <...>; "networking" = <...>; }
  importFlat = path: { exclude ? [], filter ? (_: true), sep ? "-" }:
    let
      pred = allOf [ (e: e.isNix) (excludeNames exclude) filter ];

      go = currentPath: prefix:
        let
          entries = readEntriesWhere pred currentPath;

          processEntry = entry:
            let
              newPrefix = prefix ++ [ (entryAttrName entry) ];
              key = concatStringsSep sep newPrefix;
            in
            if entry.isNixFile then
              [{ name = key; value = importEntry entry; }]
            else if entry.hasDefault then
              [{ name = key; value = importEntry entry; }] ++ (go entry.path newPrefix)
            else
              go entry.path newPrefix;
        in
        concatLists (map processEntry entries);
    in
    listToAttrs (go path []);

  # Flatten a directory tree with auto-generated aggregated modules for each directory
  # Each directory gets an entry that imports all its children recursively
  # Plus individual entries for each file
  #
  # Type: Path -> { exclude?: [String], filter?: Entry -> Bool, sep?: String } -> AttrSet
  # Example:
  #   Given: nixosModules/
  #          ├── module1.nix
  #          └── module2dir/
  #              ├── module2.nix
  #              └── module3dir/
  #                  └── module3.nix
  #
  #   importFlatWithDirs ./nixosModules { sep = "-"; }
  #   # => {
  #   #   "module1" = <module1.nix>;
  #   #   "module2dir" = { imports = [ ./module2.nix ./module3dir ]; };
  #   #   "module2dir-module2" = <module2.nix>;
  #   #   "module2dir-module3dir" = { imports = [ ./module3.nix ]; };
  #   #   "module2dir-module3dir-module3" = <module3.nix>;
  #   # }
  importFlatWithDirs = path: { exclude ? [], filter ? (_: true), sep ? "-" }:
    let
      pred = allOf [ (e: e.isNix) (excludeNames exclude) filter ];

      # Collect all importable paths from a directory (for aggregated module)
      collectImports = currentPath:
        let
          entries = readEntriesWhere pred currentPath;
        in
        map (e: e.path) (filter (e: e.isNixFile || e.hasDefault) entries)
        ++ concatLists (map (e:
          if e.isDir && !e.hasDefault then collectImports e.path else []
        ) entries);

      go = currentPath: prefix:
        let
          entries = readEntriesWhere pred currentPath;

          processEntry = entry:
            let
              newPrefix = prefix ++ [ (entryAttrName entry) ];
              key = concatStringsSep sep newPrefix;
            in
            if entry.isNixFile then
              [{ name = key; value = importEntry entry; }]
            else if entry.hasDefault then
              [{ name = key; value = importEntry entry; }] ++ (go entry.path newPrefix)
            else
              let
                childImports = collectImports entry.path;
                aggregatedModule = { imports = childImports; };
              in
              [{ name = key; value = aggregatedModule; }] ++ (go entry.path newPrefix);
        in
        concatLists (map processEntry entries);
    in
    listToAttrs (go path []);

  # Import modules as a list (useful for NixOS/home-manager modules)
  #
  # Type: Path -> { exclude?: [String], filter?: Entry -> Bool } -> [Path]
  # Example:
  #   modules = importModuleList ./modules { exclude = [ "experimental" ]; };
  importModuleList = path: { exclude ? [], filter ? (_: true) }:
    let
      pred = allOf [
        (e: e.isNix)
        (excludeNames exclude)
        filter
        (e: e.isNixFile || e.hasDefault)
      ];
    in
    map (e: e.path) (readEntriesWhere pred path);

  # Recursively collect all module paths
  #
  # Type: Path -> { exclude?: [String], filter?: Entry -> Bool } -> [Path]
  importModuleListRecursive = path: { exclude ? [], filter ? (_: true) }:
    let
      pred = allOf [ (e: e.isNix) (excludeNames exclude) filter ];

      collectPaths = entry:
        if entry.isNixFile then
          [ entry.path ]
        else if entry.hasDefault then
          [ entry.path ]
        else
          importModuleListRecursive entry.path { inherit exclude filter; };
    in
    concatLists (map collectPaths (readEntriesWhere pred path));
}
