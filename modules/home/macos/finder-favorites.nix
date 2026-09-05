{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.macos.finderFavorites;

  homeDir = config.home.homeDirectory;
  homePrefix = "${homeDir}/";

  standardUserDirNames = [
    "desktop"
    "documents"
    "download"
    "music"
    "pictures"
    "publicShare"
    "videos"
  ];

  standardUserDirs = lib.filter (path: path != null) (
    map (name: config.xdg.userDirs.${name}) standardUserDirNames
  );

  extraUserDirs = lib.attrValues (
    lib.filterAttrs (_: path: lib.isString path && lib.hasPrefix homePrefix path) (
      config.xdg.userDirs.extraConfig or { }
    )
  );

  mkDefaultEntry = path: {
    id = "xdg-${builtins.substring 0 16 (builtins.hashString "sha256" path)}";
    label = baseNameOf path;
    inherit path;
    onMissing = "skip";
  };

  defaultEntries = map mkDefaultEntry (lib.unique (standardUserDirs ++ extraUserDirs));

  normalizedEntries = map (entry: {
    id =
      if entry.id != null then
        entry.id
      else
        "path-${builtins.substring 0 24 (builtins.hashString "sha256" entry.path)}";
    inherit (entry) label path onMissing;
  }) cfg.entries;

  configuration = {
    schemaVersion = 1;
    inherit (cfg) placement;
    entries = normalizedEntries;
  };

  configurationFile = config.xdg.configFile."finder-favorites/config.json".source;
  executable = lib.getExe cfg.package;
  inherit (cfg) stateDirectory;
  initializedMarker = "${stateDirectory}/initialized-v1";
in
{
  options.macos.finderFavorites = {
    enable = lib.mkEnableOption "declarative Finder Favorites management";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.finder-favorites;
      defaultText = lib.literalExpression "pkgs.finder-favorites";
      description = "Finder Favorites reconciliation tool.";
    };

    mode = lib.mkOption {
      type = lib.types.enum [
        "manual"
        "initialize"
        "reconcile"
      ];
      default = "manual";
      description = ''
        How Home Manager uses the generated configuration. `manual` installs
        the tool and writes its config without changing Finder. `initialize`
        applies it once. `reconcile` repairs drift on every activation.
      '';
    };

    allowDeprecatedBackend = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Explicit acknowledgement that Apple deprecated LSSharedFileList and
        provides no supported programmatic Finder Favorites replacement.
      '';
    };

    placement = lib.mkOption {
      type = lib.types.enum [
        "top"
        "bottom"
      ];
      default = "bottom";
      description = "Placement of the managed block relative to unmanaged favorites.";
    };

    entries = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            id = lib.mkOption {
              type = lib.types.nullOr lib.types.nonEmptyStr;
              default = null;
              description = "Stable declarative ID. A path-derived ID is used when null.";
            };

            label = lib.mkOption {
              type = lib.types.nonEmptyStr;
              description = "Visible Finder sidebar label. Labels need not be unique.";
            };

            path = lib.mkOption {
              type = lib.types.strMatching "^/.*";
              description = "Absolute directory path used as the entry identity.";
            };

            onMissing = lib.mkOption {
              type = lib.types.enum [
                "error"
                "skip"
                "createDirectory"
              ];
              default = "error";
              description = "Policy when the configured directory does not exist.";
            };
          };
        }
      );
      default = defaultEntries;
      defaultText = "the enabled XDG user directories";
      description = ''
        Additive managed entries. Unlisted Finder favorites are preserved in
        their existing relative order.
      '';
    };

    stateDirectory = lib.mkOption {
      type = lib.types.strMatching "^/.*";
      default = "${config.xdg.stateHome}/finder-favorites";
      defaultText = lib.literalExpression ''config.xdg.stateHome + "/finder-favorites"'';
      description = "Private lock, transaction journal, and initialization state directory.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (lib.hm.assertions.assertPlatform "macos.finderFavorites" pkgs lib.platforms.darwin)
      {
        assertion = cfg.mode == "manual" || cfg.allowDeprecatedBackend;
        message = ''
          macos.finderFavorites.mode = "${cfg.mode}" writes through Apple's
          deprecated LSSharedFileList API. Set allowDeprecatedBackend = true
          only after accepting that compatibility may change on a future macOS.
        '';
      }
      {
        assertion =
          builtins.length (lib.unique (map (entry: entry.id) normalizedEntries))
          == builtins.length normalizedEntries;
        message = "macos.finderFavorites.entries must have unique IDs.";
      }
      {
        assertion =
          builtins.length (lib.unique (map (entry: entry.path) normalizedEntries))
          == builtins.length normalizedEntries;
        message = "macos.finderFavorites.entries must have unique paths.";
      }
    ];

    home.packages = [ cfg.package ];

    xdg.configFile."finder-favorites/config.json".text = builtins.toJSON configuration;

    home.activation = lib.mkMerge [
      (lib.mkIf (cfg.mode == "initialize") {
        syncFinderFavorites = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [[ ! -e ${lib.escapeShellArg initializedMarker} ]]; then
            run ${lib.escapeShellArg executable} apply \
              --config ${lib.escapeShellArg configurationFile} \
              --state-directory ${lib.escapeShellArg stateDirectory}
            run ${lib.getExe' pkgs.coreutils "mkdir"} -p -m 0700 \
              ${lib.escapeShellArg stateDirectory}
            run ${lib.getExe' pkgs.coreutils "touch"} \
              ${lib.escapeShellArg initializedMarker}
          fi
        '';
      })
      (lib.mkIf (cfg.mode == "reconcile") {
        syncFinderFavorites = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${lib.escapeShellArg executable} apply \
            --config ${lib.escapeShellArg configurationFile} \
            --state-directory ${lib.escapeShellArg stateDirectory}
        '';
      })
    ];
  };
}
