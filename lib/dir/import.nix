# High-level import functions
#
# Functions for importing directory trees in various ways
{ lib, self, ... }:
let
  inherit (builtins) concatLists listToAttrs hasAttr;
  inherit (lib) concatStringsSep;
  inherit (self)
    readEntriesWhere
    allOf
    excludeNames
    entryAttrName
    importEntry
    entriesToAttrs
    ;
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
  importNix =
    path:
    {
      exclude ? [ ],
      filter ? (_: true),
    }:
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
  importNixRecursive =
    path:
    {
      exclude ? [ ],
      filter ? (_: true),
    }:
    let
      pred = allOf [
        (e: e.isNix)
        (excludeNames exclude)
        filter
      ];

      processEntry =
        entry:
        if entry.isNixFile then
          importEntry entry
        else if entry.hasDefault then
          importEntry entry
        else
          importNixRecursive entry.path { inherit exclude filter; };

      entries = readEntriesWhere pred path;
    in
    listToAttrs (
      map (e: {
        name = entryAttrName e;
        value = processEntry e;
      }) entries
    );

  # Flatten a directory tree into a single-level attrset with path-based keys
  # Useful for module systems that need flat namespaces
  #
  # Type: Path -> { exclude?: [String], filter?: Entry -> Bool, sep?: String } -> AttrSet
  # Example:
  #   importFlat ./modules { sep = "-"; }
  #   # => { "hardware-gpu-nvidia" = <...>; "networking" = <...>; }
  importFlat =
    path:
    {
      exclude ? [ ],
      filter ? (_: true),
      sep ? "-",
    }:
    let
      pred = allOf [
        (e: e.isNix)
        (excludeNames exclude)
        filter
      ];

      go =
        currentPath: prefix:
        let
          entries = readEntriesWhere pred currentPath;

          processEntry =
            entry:
            let
              newPrefix = prefix ++ [ (entryAttrName entry) ];
              key = concatStringsSep sep newPrefix;
            in
            if entry.isNixFile then
              [
                {
                  name = key;
                  value = importEntry entry;
                }
              ]
            else if entry.hasDefault then
              [
                {
                  name = key;
                  value = importEntry entry;
                }
              ]
              ++ (go entry.path newPrefix)
            else
              go entry.path newPrefix;
        in
        concatLists (map processEntry entries);
    in
    listToAttrs (go path [ ]);

  # Flatten a directory tree into a single-level attrset for use as NixOS/home-manager modules
  # Each directory gets an entry that imports all its children recursively
  # Plus individual entries for each file
  #
  # Values are PATHS (not eagerly imported) so the NixOS module system can:
  #   - Track _file for better error messages
  #   - Deduplicate identical module imports
  #   - Evaluate modules lazily with proper module arguments
  #
  # For directories WITH default.nix: returns the directory path (Nix resolves to default.nix)
  # For directories WITHOUT default.nix: creates an aggregated module { imports = [...]; }
  # For .nix files: returns the file path directly
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
  #   #   "module1" = ./module1.nix;                       # Path to .nix file
  #   #   "module2dir" = ./module2dir;                     # Path to dir (uses default.nix)
  #   #   "module2dir-module2" = ./module2dir/module2.nix;
  #   #   "module2dir-module3dir" = { imports = [...]; };  # No default.nix, aggregates
  #   #   "module2dir-module3dir-module3" = ./module2dir/module3dir/module3.nix;
  #   # }
  #
  #   # Without default.nix in module2dir:
  #   # => {
  #   #   "module1" = ./module1.nix;
  #   #   "module2dir" = { imports = [ ./module2.nix ./module3dir/module3.nix ]; };
  #   #   "module2dir-module2" = ./module2dir/module2.nix;
  #   #   "module2dir-module3dir" = { imports = [ ./module3.nix ]; };
  #   #   "module2dir-module3dir-module3" = ./module2dir/module3dir/module3.nix;
  #   # }
  importFlatWithDirs =
    path:
    {
      exclude ? [ ],
      filter ? (_: true),
      sep ? "-",
    }:
    let
      pred = allOf [
        (e: e.isNix)
        (excludeNames exclude)
        filter
      ];

      # Recursively collect all importable paths from a directory
      # Stops recursion at directories with default.nix (they are imported as a unit)
      collectImportsRecursive =
        currentPath:
        let
          entries = readEntriesWhere pred currentPath;
          importableEntries = builtinFilter (e: e.isNixFile || e.hasDefault) entries;
          dirsWithoutDefault = builtinFilter (e: e.isDir && !e.hasDefault) entries;
        in
        map (e: e.path) importableEntries
        ++ concatLists (map (e: collectImportsRecursive e.path) dirsWithoutDefault);

      # excludeDefault: when true, skip default.nix files (used after entering a dir with default.nix)
      go =
        currentPath: prefix: excludeDefault:
        let
          baseEntries = readEntriesWhere pred currentPath;
          entries = if excludeDefault then builtinFilter (e: !e.isDefault) baseEntries else baseEntries;

          processEntry =
            entry:
            let
              newPrefix = prefix ++ [ (entryAttrName entry) ];
              key = concatStringsSep sep newPrefix;
            in
            if entry.isNixFile then
              # Return the path directly so the NixOS module system handles the import
              # This enables proper _file tracking, module deduplication, and lazy evaluation
              [
                {
                  name = key;
                  value = entry.path;
                }
              ]
            else if entry.hasDefault then
              # Directory has default.nix: return the directory path (Nix resolves to default.nix)
              # The module system will import default.nix and use it as the module
              # Pass excludeDefault=true to skip default.nix in children
              [
                {
                  name = key;
                  value = entry.path;
                }
              ]
              ++ (go entry.path newPrefix true)
            else
              # Directory without default.nix: create aggregated module with recursive imports
              let
                childImports = collectImportsRecursive entry.path;
                aggregatedModule = {
                  imports = childImports;
                };
              in
              [
                {
                  name = key;
                  value = aggregatedModule;
                }
              ]
              ++ (go entry.path newPrefix false);
        in
        concatLists (map processEntry entries);
    in
    listToAttrs (go path [ ] false);

  # Import modules as a list (useful for NixOS/home-manager modules)
  #
  # Type: Path -> { exclude?: [String], filter?: Entry -> Bool } -> [Path]
  # Example:
  #   modules = importModuleList ./modules { exclude = [ "experimental" ]; };
  importModuleList =
    path:
    {
      exclude ? [ ],
      filter ? (_: true),
    }:
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
  importModuleListRecursive =
    path:
    {
      exclude ? [ ],
      filter ? (_: true),
    }:
    let
      pred = allOf [
        (e: e.isNix)
        (excludeNames exclude)
        filter
      ];

      collectPaths =
        entry:
        if entry.isNixFile then
          [ entry.path ]
        else if entry.hasDefault then
          [ entry.path ]
        else
          importModuleListRecursive entry.path { inherit exclude filter; };
    in
    concatLists (map collectPaths (readEntriesWhere pred path));

  # Import shared modules filtered by class type (nixos, darwin, homeManager, etc.)
  # Each file in the shared directory should export an attrset with class-specific modules:
  #   { nixos = <module>; darwin = <module>; homeManager = <module>; }
  # Or a function returning such an attrset:
  #   { ... }: { nixos = <module>; darwin = <module>; }
  #
  # Only modules matching the specified class are included in the output.
  # Directories without default.nix create aggregated modules that import all
  # class-matching children recursively.
  #
  # Type: Path -> { class: String, args?: AttrSet, exclude?: [String], filter?: Entry -> Bool, sep?: String } -> AttrSet
  # Example:
  #   Given: shared/
  #          ├── home-manager.nix    # { nixos = ...; darwin = ...; }
  #          └── testdir/
  #              ├── test1.nix       # { nixos = ...; }
  #              └── testdir2/
  #                  └── test2.nix   # { nixos = ...; darwin = ...; }
  #
  #   importSharedFlat ./shared { class = "nixos"; sep = "-"; }
  #   # => {
  #   #   "home-manager" = <nixos module from home-manager.nix>;
  #   #   "testdir" = { imports = [ <nixos from test1> <nixos from testdir2/test2> ]; };
  #   #   "testdir-test1" = <nixos module from test1.nix>;
  #   #   "testdir-testdir2" = { imports = [ <nixos from test2> ]; };
  #   #   "testdir-testdir2-test2" = <nixos module from test2.nix>;
  #   # }
  #
  #   importSharedFlat ./shared { class = "darwin"; sep = "-"; }
  #   # => {
  #   #   "home-manager" = <darwin module from home-manager.nix>;
  #   #   "testdir" = { imports = [ <darwin from testdir2/test2> ]; };  # test1.nix has no darwin
  #   #   "testdir-testdir2" = { imports = [ <darwin from test2> ]; };
  #   #   "testdir-testdir2-test2" = <darwin module from test2.nix>;
  #   # }
  importSharedFlat =
    path:
    {
      class,
      args ? { },
      exclude ? [ ],
      filter ? (_: true),
      sep ? "-",
    }:
    let
      pred = allOf [
        (e: e.isNix)
        (excludeNames exclude)
        filter
      ];

      # Normalize imported value: if it's a function, call it with provided args to get the attrset
      normalizeImport = imported: if builtins.isFunction imported then imported args else imported;

      # Import a file/dir and extract the class-specific module
      importWithClass =
        entry:
        let
          raw = importEntry entry;
          imported = normalizeImport raw;
        in
        if builtins.isAttrs imported && hasAttr class imported then imported.${class} else null;

      # Check if an entry (file or dir) has any modules for the given class

      # Recursively collect all class-matching module values from a directory
      # Returns a list of extracted class modules (not paths)
      collectClassModulesRecursive =
        currentPath:
        let
          entries = readEntriesWhere pred currentPath;
          processEntry =
            e:
            if e.isNixFile then
              let
                module = importWithClass e;
              in
              if module != null then [ module ] else [ ]
            else if e.hasDefault then
              let
                module = importWithClass e;
              in
              if module != null then [ module ] else [ ]
            else
              collectClassModulesRecursive e.path;
        in
        concatLists (map processEntry entries);

      # excludeDefault: when true, skip default.nix files
      go =
        currentPath: prefix: excludeDefault:
        let
          baseEntries = readEntriesWhere pred currentPath;
          entries = if excludeDefault then builtinFilter (e: !e.isDefault) baseEntries else baseEntries;

          processEntry =
            entry:
            let
              newPrefix = prefix ++ [ (entryAttrName entry) ];
              key = concatStringsSep sep newPrefix;
            in
            if entry.isNixFile then
              let
                module = importWithClass entry;
              in
              if module != null then
                [
                  {
                    name = key;
                    value = module;
                  }
                ]
              else
                [ ]
            else if entry.hasDefault then
              let
                module = importWithClass entry;
              in
              if module != null then
                [
                  {
                    name = key;
                    value = module;
                  }
                ]
                ++ (go entry.path newPrefix true)
              else
                # Even if default.nix doesn't have the class, still recurse for children
                go entry.path newPrefix true
            else
              # Directory without default.nix: create aggregated module if any children match
              let
                childModules = collectClassModulesRecursive entry.path;
                hasMatchingChildren = childModules != [ ];
                aggregatedModule = {
                  imports = childModules;
                };
              in
              (
                if hasMatchingChildren then
                  [
                    {
                      name = key;
                      value = aggregatedModule;
                    }
                  ]
                else
                  [ ]
              )
              ++ (go entry.path newPrefix false);
        in
        concatLists (map processEntry entries);
    in
    listToAttrs (go path [ ] false);

  # Import host configurations from a directory where each subdirectory is a host
  # Each host folder should have a default.nix that returns host configuration options.
  #
  # The default.nix in each host folder receives { tree, folderName, ... } and should return:
  #   { system, hostName?, modules, nixpkgsArgs?, specialArgs?, ... }
  #
  # This function uses mkHost to build the final system configuration for each host.
  #
  # Type: Path -> {
  #   mkHost: Function,           # The mkHost builder function (from lib.configs.mkHost)
  #   withSystem: Function,       # flake-parts withSystem
  #   inputs: AttrSet,            # Flake inputs
  #   self: AttrSet,              # Flake self
  #   builder: Function,          # System builder (e.g., lib.nixosSystem)
  #   modules: AttrSet,           # Available modules to pass to host configs
  #   exclude?: [String],         # Host folder names to exclude
  #   filter?: Entry -> Bool,     # Additional filter predicate for entries
  # } -> AttrSet
  #
  # Example:
  #   Given: configs/nixos/
  #          ├── desktop/
  #          │   └── default.nix    # { modules, ... }: { system = "x86_64-linux"; ... }
  #          └── laptop/
  #              └── default.nix    # { modules, ... }: { system = "x86_64-linux"; ... }
  #
  #   importHosts ./configs/nixos {
  #     mkHost = myLib.configs.mkHost;
  #     inherit withSystem inputs self;
  #     builder = lib.nixosSystem;
  #     modules = config.flake.modules.nixos;
  #   }
  #   # => {
  #   #   "desktop" = <nixosConfiguration for desktop>;
  #   #   "laptop" = <nixosConfiguration for laptop>;
  #   # }
  importHosts =
    path:
    {
      mkHost,
      connectHomeDarwin,
      connectHomeNixos,
      withSystem,
      inputs,
      self,
      builder,
      modules,
      homeConfigs ? { },
      extraSpecialArgs ? { },
      exclude ? [ ],
      filter ? (_: true),
    }:
    let
      # Only include directories with default.nix (valid host configurations)
      pred = allOf [
        (e: e.isDir)
        (e: e.hasDefault)
        (excludeNames exclude)
        filter
      ];

      hostEntries = readEntriesWhere pred path;

      # Build a single host configuration
      buildHost =
        entry:
        let
          folderName = entryAttrName entry;

          modulesPath = entry.path + /modules;
          # add config's modules to the modules set (only if modules dir exists)
          configModules =
            if builtins.pathExists modulesPath then importFlatWithDirs modulesPath { sep = "-"; } else { };
          combinedModules = lib.attrsets.unionOfDisjoint modules configModules;

          # Import the host's default.nix and call it with configuration arguments
          hostConfigFn = importEntry entry;
          hostConfig = hostConfigFn {
            inherit inputs self;
            inherit connectHomeDarwin connectHomeNixos;
            modules = combinedModules;
          };

          # Create the mkHost builder with the provided arguments
          hostBuilder = mkHost {
            inherit
              withSystem
              inputs
              self
              builder
              homeConfigs
              extraSpecialArgs
              ;
          };
        in
        {
          name = folderName;
          value = hostBuilder (hostConfig // { inherit folderName; });
        };
    in
    listToAttrs (map buildHost hostEntries);

  # Import home configurations from a directory where each subdirectory is a home config
  # Each home folder should have a default.nix that returns home configuration options.
  #
  # The default.nix in each home folder receives { modules, folderName, ... } and should return:
  #   { system, username, homeDirectory, modules, stateVersion?, nixpkgsArgs?, extraSpecialArgs? }
  #
  # This function uses mkHome to build the final Home Manager configuration for each entry.
  # The output key defaults to "username@folderName" but can be overridden via configName.
  #
  # Type: Path -> {
  #   mkHome: Function,           # The mkHome builder function (from lib.configs.mkHome)
  #   withSystem: Function,       # flake-parts withSystem
  #   inputs: AttrSet,            # Flake inputs
  #   self: AttrSet,              # Flake self
  #   modules: AttrSet,           # Available homeManager modules
  #   exclude?: [String],         # Home folder names to exclude
  #   filter?: Entry -> Bool,     # Additional filter predicate for entries
  # } -> AttrSet
  #
  # Example:
  #   Given: configs/home/
  #          ├── desktop/
  #          │   └── default.nix    # { modules, ... }: { system = "x86_64-linux"; username = "ianmh"; ... }
  #          └── macbook-pro-m4/
  #              └── default.nix    # { modules, ... }: { system = "aarch64-darwin"; username = "ianmh"; ... }
  #
  #   importHomes ./configs/home {
  #     mkHome = myLib.configs.mkHome;
  #     inherit withSystem inputs self;
  #     modules = config.flake.modules.homeManager;
  #   }
  #   # => {
  #   #   "ianmh@desktop" = <homeManagerConfiguration for desktop>;
  #   #   "ianmh@macbook-pro-m4" = <homeManagerConfiguration for macbook-pro-m4>;
  #   # }
  importHomes =
    path:
    {
      mkHome,
      withSystem,
      inputs,
      self,
      modules,
      extraSpecialArgs ? { },
      exclude ? [ ],
      filter ? (_: true),
    }:
    let
      # Only include directories with default.nix (valid home configurations)
      pred = allOf [
        (e: e.isDir)
        (e: e.hasDefault)
        (excludeNames exclude)
        filter
      ];

      homeEntries = readEntriesWhere pred path;

      # Build a single home configuration
      buildHome =
        entry:
        let
          folderName = entryAttrName entry;

          # Create the mkHome builder with the provided arguments
          homeBuilder = mkHome { inherit withSystem inputs self; };

          # create home config
          homeConfig = createHomeConfig entry { inherit inputs self modules; };

          # Default config name is "username@folderName"
          configName = homeConfig.configName or "${homeConfig.username}@${folderName}";
        in
        {
          name = configName;
          value = homeBuilder (
            homeConfig
            // {
              inherit folderName;
              extraSpecialArgs = (homeConfig.extraSpecialArgs or { }) // extraSpecialArgs;
            }
          );
        };
    in
    listToAttrs (map buildHome homeEntries);

  createHomeConfig =
    entry:
    {
      inputs,
      self,
      modules,
    }:
    let
      modulesPath = entry.path + /modules;
      # add config's modules to the modules set (only if modules dir exists)
      configModules =
        if builtins.pathExists modulesPath then importFlatWithDirs modulesPath { sep = "-"; } else { };
      combinedModules = lib.attrsets.unionOfDisjoint modules configModules;

      # Import the home config's default.nix and call it with available modules
      homeConfigFn = importEntry entry;
      homeConfig = homeConfigFn {
        inherit inputs self;
        modules = combinedModules;
      };
    in
    homeConfig;

  importHomeConfigs =
    path:
    {
      inputs,
      self,
      modules,
      exclude ? [ ],
      filter ? (_: true),
    }:
    let
      pred = allOf [
        (e: e.isDir)
        (e: e.hasDefault)
        (excludeNames exclude)
        filter
      ];

      homeEntries = readEntriesWhere pred path;

      getHomeConfig =
        prependUsername: entry:
        let
          folderName = entryAttrName entry;
          homeConfig = createHomeConfig entry { inherit inputs self modules; };

          configName =
            homeConfig.configName
              or (if prependUsername then "${homeConfig.username}@${folderName}" else folderName);
        in
        {
          name = configName;
          value = homeConfig // {
            inherit folderName;
          };
        };

      homeConfigs = listToAttrs (
        lib.concatLists [
          (map (getHomeConfig true) homeEntries)
          (map (getHomeConfig false) homeEntries)
        ]
      );
    in
    homeConfigs;
}
