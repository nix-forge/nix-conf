{ pkgs, lib, ... }: {
  reason = "Jellyfin mutates shared caption defaults when reading one account's saved appearance.";
  upstream = "https://github.com/jellyfin/jellyfin-web/blob/v12.2/src/scripts/settings/userSettings.js";
  removal = "The upstream caption getter merges into a fresh object so account changes cannot alter defaults.";
  reviewedRevision = "1d060086d60cb76a40cf37109f979d88a5bd6396";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/jellyfin-caption-defaults.patch ];
      postPatch = (old.postPatch or "") + ''
        ${lib.getExe pkgs.nodejs_24} ${./patches/jellyfin-caption-settings-test.cts} src/scripts/settings/userSettings.js
      '';
    });
}
