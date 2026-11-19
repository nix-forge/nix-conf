{
  lib,
  myLib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.macos.dockItems;
  moduleFormatVersion = 2;

  dockutilExe = lib.getExe cfg.package;
  dockStateHelper = (import ../../../flake/runtime-packages.nix { inherit pkgs; }).dockState;

  absolutePathType = lib.types.strMatching "^/.*";
  appBundlePathType = lib.types.strMatching "^/.+\\.app$";

  managedAppsDirectory =
    if config.targets.darwin.copyApps.enable then
      config.targets.darwin.copyApps.directory
    else if config.targets.darwin.linkApps.enable then
      config.targets.darwin.linkApps.directory
    else
      null;

  hasManagedApps = builtins.any (item: item ? hmApp || item ? package) cfg.persistentApps;

  # getDarwinApp validates the standard metadata; only retain its bundle name.
  # Dock tiles must open the managed copy, rather than the immutable store app.
  managedAppName =
    item: if item ? package then baseNameOf (lib.getDarwinApp item.package) else "${item.hmApp}.app";

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

  appPath =
    item:
    if item ? hmApp || item ? package then
      "${config.home.homeDirectory}/${managedAppsDirectory}/${managedAppName item}"
    else
      item.app;

  resolvedPersistentApps = map (
    item:
    if item ? hmApp || item ? package then
      {
        type = "hmApp";
        name = lib.removeSuffix ".app" (managedAppName item);
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

  # Nix supplies ordered data; the native reconciler owns preflight and commit.
  dockActions = [
    [
      "--remove"
      "all"
    ]
  ]
  ++ map (
    item:
    if item ? spacer then
      [
        "--add"
        ""
        "--type"
        (if item.spacer.small then "small-spacer" else "spacer")
        "--section"
        "apps"
        "--position"
        "end"
      ]
    else
      [
        "--add"
        (appPath item)
        "--section"
        "apps"
        "--position"
        "end"
      ]
  ) cfg.persistentApps
  ++ map (item: [
    "--add"
    item.folder.path
    "--section"
    "others"
    "--view"
    showAsMap.${item.folder.showAs}
    "--display"
    item.folder.displayAs
    "--sort"
    arrangementMap.${item.folder.arrangement}
    "--position"
    "end"
  ]) cfg.persistentOthers;

  dockTargets =
    map appPath (builtins.filter (item: !(item ? spacer)) cfg.persistentApps)
    ++ map (item: item.folder.path) cfg.persistentOthers;

  taggedAppType = lib.types.attrTag {
    package = lib.mkOption {
      type = lib.types.package;
      description = "Package whose meta.mainDarwinApp identifies an application installed by Home Manager, including configured package variants.";
    };

    hmApp = lib.mkOption {
      type = lib.types.strMatching "[^/]+";
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
        { package = pkgs.ghostty-bin; }
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
          `macos.dockItems.persistentApps` contains managed application entries, but neither
          `targets.darwin.copyApps.enable` nor `targets.darwin.linkApps.enable` is enabled.
        '';
      }
      {
        assertion = lib.all (
          item:
          !(item ? package)
          || lib.any (
            package: (package.meta.mainDarwinApp or null) == managedAppName item
          ) config.home.packages
        ) cfg.persistentApps;
        message = "macos.dockItems package entries must identify an application supplied by home.packages.";
      }
    ];

    home.activation.syncDockItems = lib.hm.dag.entryAfter activationDeps (
      myLib.writers.renderBashText { inherit pkgs; }
        {
          name = "sync-dock-items.sh";
          text = ''
            # shellcheck shell=bash
            DRY_RUN="''${DRY_RUN:-}" @dockSyncExe@ @dockPolicy@
          '';
        }
        {
          dockSyncExe = lib.getExe' dockStateHelper "hm-dock-sync";
          dockPolicy = pkgs.writeText "dock-policy.json" (
            builtins.toJSON {
              inherit (cfg) mode;
              configHash = dockStateHash;
              cacheDirectory = "${dockCacheDirectory}/home-manager-macos";
              dockutil = dockutilExe;
              actions = dockActions;
              targets = dockTargets;
            }
          );
        }
    );
  };
}
