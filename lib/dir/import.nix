# High-level import functions
#
# Functions for importing directory trees in various ways
{ lib, self, ... }:
let
  inherit (builtins) concatLists listToAttrs;
  inherit (lib) concatStringsSep;
  inherit (self) readEntriesWhere allOf excludeNames entryAttrName importEntry entriesToAttrs;
  builtinFilter = builtins.filter;
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
  # For directories WITH default.nix: uses the default.nix as the import
  # For directories WITHOUT default.nix: creates an aggregated module importing all files recursively
  #
  # Type: Path -> { exclude?: [String], filter?: Entry -> Bool, sep?: String } -> AttrSet
  # Example:
  #   Given: nixosModules/
  #          ├── module1.nix
  #          └── module2dir/
  #              ├── default.nix      # If present, used as "module2dir" entry
  #              ├── module2.nix
  #              └── module3dir/
  #                  └── module3.nix
  #
  #   importFlatWithDirs ./nixosModules { sep = "-"; }
  #   # With default.nix in module2dir:
  #   # => {
  #   #   "module1" = <module1.nix>;
  #   #   "module2dir" = <default.nix>;                    # Uses default.nix directly
  #   #   "module2dir-module2" = <module2.nix>;
  #   #   "module2dir-module3dir" = { imports = [...]; };  # No default.nix, aggregates
  #   #   "module2dir-module3dir-module3" = <module3.nix>;
  #   # }
  #
  #   # Without default.nix in module2dir:
  #   # => {
  #   #   "module1" = <module1.nix>;
  #   #   "module2dir" = { imports = [ ./module2.nix ./module3dir/module3.nix ]; };
  #   #   "module2dir-module2" = <module2.nix>;
  #   #   "module2dir-module3dir" = { imports = [ ./module3.nix ]; };
  #   #   "module2dir-module3dir-module3" = <module3.nix>;
  #   # }
  importFlatWithDirs = path: { exclude ? [], filter ? (_: true), sep ? "-" }:
    let
      pred = allOf [ (e: e.isNix) (excludeNames exclude) filter ];

      # Recursively collect all importable paths from a directory
      # Stops recursion at directories with default.nix (they are imported as a unit)
      collectImportsRecursive = currentPath:
        let
          entries = readEntriesWhere pred currentPath;
          importableEntries = builtinFilter (e: e.isNixFile || e.hasDefault) entries;
          dirsWithoutDefault = builtinFilter (e: e.isDir && !e.hasDefault) entries;
        in
        map (e: e.path) importableEntries
        ++ concatLists (map (e: collectImportsRecursive e.path) dirsWithoutDefault);

      # excludeDefault: when true, skip default.nix files (used after entering a dir with default.nix)
      go = currentPath: prefix: excludeDefault:
        let
          baseEntries = readEntriesWhere pred currentPath;
          entries = if excludeDefault then builtinFilter (e: !e.isDefault) baseEntries else baseEntries;

          processEntry = entry:
            let
              newPrefix = prefix ++ [ (entryAttrName entry) ];
              key = concatStringsSep sep newPrefix;
            in
            if entry.isNixFile then
              [{ name = key; value = importEntry entry; }]
            else if entry.hasDefault then
              # Directory has default.nix: use it as the import, then recurse for children
              # Pass excludeDefault=true to skip default.nix in children
              [{ name = key; value = importEntry entry; }] ++ (go entry.path newPrefix true)
            else
              # Directory without default.nix: create aggregated module with recursive imports
              let
                childImports = collectImportsRecursive entry.path;
                aggregatedModule = { imports = childImports; };
              in
              [{ name = key; value = aggregatedModule; }] ++ (go entry.path newPrefix false);
        in
        concatLists (map processEntry entries);
    in
    listToAttrs (go path [] false);

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
