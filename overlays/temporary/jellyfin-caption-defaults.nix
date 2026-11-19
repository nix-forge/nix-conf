_: {
  reason = "Jellyfin mutates shared caption defaults when reading one account's saved appearance.";
  upstream = "https://github.com/jellyfin/jellyfin-web/blob/v12.2/src/scripts/settings/userSettings.js";
  removal = "The upstream caption getter merges into a fresh object so account changes cannot alter defaults.";
  reviewedRevision = "04906337b6d53e8bb0eaf0470ae9f070a4d4eb55";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/jellyfin-caption-defaults.patch ];
    });
}
