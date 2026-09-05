{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.macos.dockItems;
  moduleFormatVersion = 2;

  dockutilExe = lib.getExe cfg.package;
  dockStateHelper = pkgs.writers.writePython3Bin "hm-dock-state" { } (
    builtins.readFile ./dock_state.py
  );
  dockStateExe = lib.getExe dockStateHelper;

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
    "setDarwinDefaults"
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
    ''
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
    ''
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

  # Validate everything before touching the Dock.  Without this preflight,
  # an unavailable app can leave the Dock half-rebuilt after `--remove all`.
  validateTargets = lib.concatStringsSep "\n" (
    (map (item: lib.optionalString (!(item ? spacer)) (validateApp item)) cfg.persistentApps)
    ++ (map (item: validateFolder item.folder) cfg.persistentOthers)
  );

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
      inherit (cfg) mode;
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

    mode = lib.mkOption {
      type = lib.types.enum [
        "authoritative"
        "initialize"
      ];
      default = "authoritative";
      description = ''
        Reconciliation policy. Authoritative repairs changes made outside Nix.
        Initialize reapplies only when the configured layout changes and then
        permits manual edits.
      '';
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
            path = "${config.home.homeDirectory}/Downloads";
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
      dock_cache_directory="${dockCacheDirectory}/home-manager-macos"
      dock_config_hash_path="$dock_cache_directory/dock-config.hash"
      dock_state_hash_path="$dock_cache_directory/dock-state.hash"
      old_config_hash=$(cat "$dock_config_hash_path" 2>/dev/null || true)
      old_state_hash=$(cat "$dock_state_hash_path" 2>/dev/null || true)
      new_config_hash="${dockStateHash}"
      current_state_hash=""
      needs_sync=""

      if [ ${lib.escapeShellArg cfg.mode} = authoritative ] && [ -z "''${DRY_RUN:-}" ]; then
        current_state_hash="$(${dockStateExe})" || exit 1
      fi

      if [ "$old_config_hash" != "$new_config_hash" ]; then
        needs_sync=1
      elif [ ${lib.escapeShellArg cfg.mode} = authoritative ] && [ "$old_state_hash" != "$current_state_hash" ]; then
        needs_sync=1
      fi

      if [ -n "$needs_sync" ] || [ -n "''${DRY_RUN:-}" ]; then
        verboseEcho "setting up Dock items..."

        if [ -z "''${DRY_RUN:-}" ] && ! ${dockutilExe} --list >/dev/null; then
          echo "error: dockutil cannot read this macOS Dock; refusing to remove any items" >&2
          exit 1
        fi

        ${validateTargets}
        ${renderCommandFns commandFns}

        if [ -z "''${DRY_RUN:-}" ]; then
          current_state_hash="$(${dockStateExe})" || exit 1
          install -d -m 0700 "$dock_cache_directory"
          printf '%s\n' "$new_config_hash" > "$dock_config_hash_path.new"
          printf '%s\n' "$current_state_hash" > "$dock_state_hash_path.new"
          chmod 0600 "$dock_config_hash_path.new" "$dock_state_hash_path.new"
          mv -f "$dock_config_hash_path.new" "$dock_config_hash_path"
          mv -f "$dock_state_hash_path.new" "$dock_state_hash_path"
        fi
      else
        verboseEcho "Dock items unchanged, skipping..."
      fi
    '';
  };
}
