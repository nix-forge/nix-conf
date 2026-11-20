{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  checkedShellText = myLib.writers.checkedShellText { inherit pkgs; };
  cfg = config.xdg.directoryBookmarks;
  dirs = config.xdg.userDirs;
  paths = lib.unique (
    lib.filter (path: path != null && path != config.home.homeDirectory) (
      map (name: dirs.${name}) [
        "desktop"
        "download"
        "documents"
        "music"
        "pictures"
        "videos"
        "projects"
        "publicShare"
        "templates"
      ]
      ++ lib.attrValues dirs.extraConfig
    )
  );
  policy = pkgs.writeText "directory-bookmarks.json" (builtins.toJSON cfg.entries);
  command = (import ../../../flake/runtime-packages.nix { inherit pkgs; }).directoryBookmarks;
in
{
  options.xdg.directoryBookmarks = {
    enable = lib.mkEnableOption "additive GTK bookmarks and KDE Places for XDG user directories" // {
      default = pkgs.stdenv.hostPlatform.isLinux;
    };
    entries = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            path = lib.mkOption {
              type = lib.types.strMatching "^/.*";
              description = "Existing directory to pin. Missing directories are skipped.";
            };
            label = lib.mkOption {
              type = lib.types.nonEmptyStr;
              description = "Sidebar label used when adding a new bookmark.";
            };
          };
        }
      );
      default = map (path: {
        inherit path;
        label = baseNameOf path;
      }) paths;
      description = ''
        Directories to add to GTK file managers and file dialogs, and KDE Places.
        Defaults to all configured XDG user directories, including extraConfig.
        Existing bookmarks, labels and ordering remain user-controlled. Removing
        an entry here does not remove a bookmark added in an earlier activation.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (lib.hm.assertions.assertPlatform "xdg.directoryBookmarks" pkgs lib.platforms.linux)
      {
        assertion = dirs.enable;
        message = "xdg.directoryBookmarks requires xdg.userDirs.enable.";
      }
      {
        assertion = config.gtk.gtk3.bookmarks == [ ];
        message = "Use xdg.directoryBookmarks.entries instead of gtk.gtk3.bookmarks to keep bookmarks writable.";
      }
    ];
    home.packages = [ command ];
    home.activation.syncDirectoryBookmarks =
      lib.hm.dag.entryAfter [ "createXdgUserDirectories" "linkGeneration" ]
        (checkedShellText {
          name = "sync-directory-bookmarks";
          text = "run ${
            lib.escapeShellArgs [
              (lib.getExe command)
              "--config"
              policy
              "--home"
              config.home.homeDirectory
              "--config-home"
              config.xdg.configHome
              "--data-home"
              config.xdg.dataHome
            ]
          }";
        });
  };
}
