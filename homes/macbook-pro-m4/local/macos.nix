{
  macos = {
    commandProfile = "native-first";

    finderFavorites = {
      enable = true;
      mode = "reconcile";
      placement = "bottom";

      # Apple provides no supported programmatic Finder Favorites API. The
      # native tool isolates the deprecated backend behind rollback and
      # verification, and this acknowledgement is required before activation.
      allowDeprecatedBackend = true;
    };
  };
}
