{
  inputs,
  pkgs,
  lib,
  config,
  self,
  system,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  spicePkgs = inputs.spicetify-nix.legacyPackages.${system};
  awkExe = lib.getExe pkgs.gawk;
  spicetifyPackage = self.packages.${system}.spicetify-cli-fixed;
  spotifyPackage = if isDarwin then self.packages.${system}.spotify-spotx else pkgs.spotify;
  spotifyEntitlements = ../../pkgs/spotify-spotx/entitlements.plist;
  spotifyDarwinInstallDir = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}";
  spotifyDarwinApp = "${spotifyDarwinInstallDir}/Spotify.app";
in
{
  imports = [ inputs.spicetify-nix.homeManagerModules.default ];

  # Nixpkgs' sandbox-friendly darwin.sigtool signs Mach-O files in the package,
  # but Spotify's CEF bundle also needs a full app resource envelope after
  # Home Manager copies the app out of the immutable store.
  home.activation.repairSpotifyDarwinAppSignature = lib.mkIf isDarwin (
    lib.hm.dag.entryAfter [ "copyApps" ] ''
      spotifyApp="${spotifyDarwinApp}"

      if [ -d "$spotifyApp" ]; then
        chmod -R u+w "$spotifyApp"
        /usr/bin/xattr -cr "$spotifyApp" 2>/dev/null || true
        /usr/bin/codesign --force --deep --options runtime --entitlements "${spotifyEntitlements}" --sign - "$spotifyApp"
        /usr/bin/codesign --verify --deep --strict --verbose=2 "$spotifyApp"
      fi
    ''
  );

  home.activation.configureSpotifyQuality = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if pgrep -x Spotify >/dev/null 2>&1 || pgrep -x spotify >/dev/null 2>&1; then
      echo "Skipping Spotify quality settings because Spotify is running."
    else
      update_pref() {
        prefs="$1"
        key="$2"
        value="$3"
        temporary_prefs="$(mktemp "''${prefs}.tmp.XXXXXX")"

        "${awkExe}" -v key="$key" -v value="$value" '
          index($0, key "=") == 1 {
            if (!found++) print key "=" value
            next
          }
          { print }
          END {
            if (!found) print key "=" value
          }
        ' "$prefs" > "$temporary_prefs"
        mv "$temporary_prefs" "$prefs"
      }

      spotify_prefs=()
      ${
        if isDarwin then
          ''
            for prefs in "${config.home.homeDirectory}"/Library/Application\ Support/Spotify/Users/*-user/prefs; do
              [ -f "$prefs" ] && spotify_prefs+=("$prefs")
            done
          ''
        else
          ''
            prefs="${config.xdg.configHome}/spotify/prefs"
            [ -f "$prefs" ] && spotify_prefs+=("$prefs")
          ''
      }

      for prefs in "''${spotify_prefs[@]}"; do
        # Spotify reports this account/device as Standard-capable, whose
        # highest streaming tier is High (3); Lossless (5) is unavailable.
        update_pref "$prefs" audio.play_bitrate_enumeration 3
        update_pref "$prefs" audio.play_bitrate_non_metered_enumeration 3
        update_pref "$prefs" audio.allow_downgrade false
      done
    fi
  '';

  programs.spicetify = {
    enable = true;
    inherit spotifyPackage;
    inherit spicetifyPackage;

    theme = lib.mkForce spicePkgs.themes.comfy;
    colorScheme = lib.mkForce "Spotify";

    enabledExtensions = with spicePkgs.extensions; [
      adblock
      volumePercentage
      shuffle
      copyLyrics
      fullAlbumDate
    ];
  };
}
