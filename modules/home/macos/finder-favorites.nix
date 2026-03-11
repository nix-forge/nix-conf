{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  homeDir = config.home.homeDirectory;
  homePrefix = "${homeDir}/";

  standardUserDirNames = [
    "desktop"
    "documents"
    "download"
    "music"
    "pictures"
    "publicShare"
    "templates"
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

  favoriteEntries = map (path: {
    label = baseNameOf path;
    inherit path;
  }) (lib.unique (standardUserDirs ++ extraUserDirs));

  finderFavoritesHelper =
    pkgs.writers.writePython3Bin "hm-sync-finder-favorites" { flakeIgnore = [ "E501" ]; }
      (
        builtins.replaceStrings
          [ "\"__DEFAULT_MYSIDES_BIN__\"" "\"__FAVORITES_JSON__\"" ]
          [
            (builtins.toJSON (lib.getExe' pkgs.mysides "mysides"))
            (builtins.toJSON (builtins.toJSON favoriteEntries))
          ]
          (builtins.readFile ./finder_favorites.py)
      );
in
{
  home.activation.syncFinderFavorites = lib.mkIf (isDarwin && config.xdg.userDirs.enable) (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${lib.getExe' finderFavoritesHelper "hm-sync-finder-favorites"}
    ''
  );
}
