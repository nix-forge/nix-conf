{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.macos.dockItems;
  moduleFormatVersion = 1;

  dockutilExe = lib.getExe cfg.package;

  absolutePathType = lib.types.strMatching "^/.*";
  appBundlePathType = lib.types.strMatching "^/.+\\.app$";

  managedAppsDirectory =
    if config.targets.darwin.copyApps.enable then
      config.targets.darwin.copyApps.directory
    else if config.targets.darwin.linkApps.enable then
      config.targets.darwin.linkApps.directory
    else
      null;

  hasManagedApps = builtins.any (item: item ? hmApp) cfg.persistentApps;

  activationDeps = [
    "writeBoundary"
  ]
  ++ lib.optionals hasManagedApps (
    if config.targets.darwin.copyApps.enable then
      [ "copyApps" ]
    else if config.targets.darwin.linkApps.enable then
      [ "linkApps" ]
    else
      [ ]
  );

  arrangementMap = {
    name = "name";
    date-added = "dateadded";
    date-modified = "datemodified";
    date-created = "datecreated";
    kind = "kind";
  };

  showAsMap = {
    automatic = "auto";
    fan = "fan";
    grid = "grid";
    list = "list";
  };

  withNoRestart = noRestart: lib.optionalString noRestart " --no-restart";

  appPath =
    item:
    if item ? hmApp then
      "${config.home.homeDirectory}/${managedAppsDirectory}/${item.hmApp}.app"
    else
      item.app;

  resolvedPersistentApps = map (
    item:
    if item ? hmApp then
      {
        type = "hmApp";
        name = item.hmApp;
        path = appPath item;
      }
    else if item ? app then
      {
        type = "app";
        path = item.app;
      }
    else
      {
        type = "spacer";
        inherit (item.spacer) small;
      }
  ) cfg.persistentApps;

  resolvedPersistentOthers = map (item: {
    type = "folder";
    inherit (item.folder)
      path
      arrangement
      displayAs
      showAs
      ;
  }) cfg.persistentOthers;

  validateApp =
    item:
    let
      path = appPath item;
      label = if item ? hmApp then "Home Manager app `${item.hmApp}`" else "app `${item.app}`";
      msg = "error: Dock item ${label} does not exist at ${path}";
    in
    ''
      if [ -z "''${DRY_RUN:-}" ] && [ ! -d ${lib.escapeShellArg path} ]; then
        echo ${lib.escapeShellArg msg} >&2
        exit 1
      fi
    '';

  validateFolder =
    folder:
    let
      msg = "error: Dock folder ${folder.path} does not exist or is not a directory";
    in
    ''
      if [ -z "''${DRY_RUN:-}" ] && [ ! -d ${lib.escapeShellArg folder.path} ]; then
        echo ${lib.escapeShellArg msg} >&2
        exit 1
      fi
    '';

  removeAllCommand = noRestart: ''
    run ${dockutilExe} --remove all${withNoRestart noRestart}
  '';

  addAppCommand =
    item: noRestart:
    let
      path = appPath item;
    in
    validateApp item
    + ''
      run ${dockutilExe} \
        --add ${lib.escapeShellArg path} \
        --section apps \
        --position end${withNoRestart noRestart}
    '';

  addSpacerCommand =
    item: noRestart:
    let
      spacerType = if item.spacer.small then "small-spacer" else "spacer";
    in
    ''
      run ${dockutilExe} \
        --add ${lib.escapeShellArg ""} \
        --type ${spacerType} \
        --section apps \
        --position end${withNoRestart noRestart}
    '';

  addOtherCommand =
    item: noRestart:
    let
      inherit (item) folder;
    in
    validateFolder folder
    + ''
      run ${dockutilExe} \
        --add ${lib.escapeShellArg folder.path} \
        --section others \
        --view ${showAsMap.${folder.showAs}} \
        --display ${folder.displayAs} \
        --sort ${arrangementMap.${folder.arrangement}} \
        --position end${withNoRestart noRestart}
    '';

  commandFns = [
    removeAllCommand
  ]
  ++ map (
    item: if item ? spacer then addSpacerCommand item else addAppCommand item
  ) cfg.persistentApps
  ++ map addOtherCommand cfg.persistentOthers;

  renderCommandFns =
    fns: lib.concatStringsSep "\n" (map (fn: fn true) (lib.init fns) ++ [ (lib.last fns false) ]);

  taggedAppType = lib.types.attrTag {
    hmApp = lib.mkOption {
      type = lib.types.str;
      description = "Name of an app bundle inside the Home Manager apps directory, without the .app suffix.";
    };

    app = lib.mkOption {
      type = appBundlePathType;
      description = "Absolute path to a macOS .app bundle.";
    };

    spacer = lib.mkOption {
      type = lib.types.submodule {
        options.small = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether the spacer should use dockutil's small-spacer tile type.";
        };
      };
      description = "Spacer tile to add to the apps section.";
    };
  };

  folderType = lib.types.submodule {
    options = {
      path = lib.mkOption {
        type = absolutePathType;
        description = "Absolute path to a folder to add to the Dock's others section.";
      };

      arrangement = lib.mkOption {
        type = lib.types.enum [
          "name"
          "date-added"
          "date-modified"
          "date-created"
          "kind"
        ];
        default = "name";
        description = "Sort order for the folder contents.";
      };

      displayAs = lib.mkOption {
        type = lib.types.enum [
          "stack"
          "folder"
        ];
        default = "stack";
        description = "How the Dock should display the folder before opening it.";
      };

      showAs = lib.mkOption {
        type = lib.types.enum [
          "automatic"
          "fan"
          "grid"
          "list"
        ];
        default = "automatic";
        description = "How the Dock should show the folder contents when opened.";
      };
    };
  };

  taggedOtherType = lib.types.attrTag {
    folder = lib.mkOption {
      type = folderType;
      description = "Folder item to add to the Dock's others section.";
    };
  };

  # Include rendered paths and tool inputs so activation reruns when the
  # effective Dock output changes, not only when the raw option list changes.
  dockStateHash = builtins.hashString "sha256" (
    builtins.toJSON {
      formatVersion = moduleFormatVersion;
      packagePath = cfg.package.outPath;
      appsDirectory = managedAppsDirectory;
      apps = resolvedPersistentApps;
      others = resolvedPersistentOthers;
    }
  );

  dockCacheDirectory =
    if config.xdg.enable then config.xdg.cacheHome else "${config.home.homeDirectory}/.cache";

in
{
  options.macos.dockItems = {
    enable = lib.mkEnableOption "declarative macOS Dock items";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.dockutil;
      defaultText = lib.literalExpression "pkgs.dockutil";
      description = "dockutil package to use for Dock management.";
    };

    persistentApps = lib.mkOption {
      type = lib.types.listOf taggedAppType;
      default = [ ];
      description = "Ordered items for the left side of the Dock.";
      example = [
        { hmApp = "Ghostty"; }
        { spacer.small = false; }
        { app = "/System/Applications/System Settings.app"; }
      ];
    };

    persistentOthers = lib.mkOption {
      type = lib.types.listOf taggedOtherType;
      default = [ ];
      description = "Ordered folder items for the right side of the Dock.";
      example = [
        {
          folder = {
            path = "/Users/example/Downloads";
            displayAs = "folder";
            showAs = "grid";
            arrangement = "date-added";
          };
        }
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (lib.hm.assertions.assertPlatform "macos.dockItems" pkgs lib.platforms.darwin)

      {
        assertion =
          !hasManagedApps || config.targets.darwin.copyApps.enable || config.targets.darwin.linkApps.enable;
        message = ''
          `macos.dockItems.persistentApps` contains `hmApp` entries, but neither
          `targets.darwin.copyApps.enable` nor `targets.darwin.linkApps.enable` is enabled.
        '';
      }
    ];

    home.activation.syncDockItems = lib.hm.dag.entryAfter activationDeps ''
      dock_hash_path="${dockCacheDirectory}/hm-dock.hash"
      old_hash=$(cat "$dock_hash_path" 2>/dev/null || echo "")
      new_hash="${dockStateHash}"

      # Always run if DRY_RUN is set to ensure we see the output,
      # otherwise only run if the configuration hash has changed.
      if [ "$old_hash" != "$new_hash" ] || [ -n "''${DRY_RUN:-}" ]; then
        verboseEcho "setting up Dock items..."
        ${renderCommandFns commandFns}

        # Save the new hash only if it's not a dry run
        if [ -z "''${DRY_RUN:-}" ]; then
          mkdir -p "$(dirname "$dock_hash_path")"
          echo "$new_hash" > "$dock_hash_path"
        fi
      else
        verboseEcho "Dock items unchanged, skipping..."
      fi
    '';
  };
}
