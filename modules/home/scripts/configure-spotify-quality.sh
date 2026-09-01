# shellcheck shell=sh
if @pgrep@ -x Spotify >/dev/null 2>&1 || @pgrep@ -x spotify >/dev/null 2>&1; then
  echo "Skipping Spotify quality settings because Spotify is running."
else
  update_pref() {
    prefs="$1"
    key="$2"
    value="$3"
    temporary_prefs="$(@mktemp@ "${prefs}.tmp.XXXXXX")"

    # shellcheck disable=SC2016 # The Awk program must receive its own $0 and variables literally.
    @awk@ -v key="$key" -v value="$value" '
      index($0, key "=") == 1 {
        if (!found++) print key "=" value
        next
      }
      { print }
      END {
        if (!found) print key "=" value
      }
    ' "$prefs" >"$temporary_prefs"
    @mv@ "$temporary_prefs" "$prefs"
  }

  # shellcheck disable=SC2043 # Nix substitutes a quoted path plus an unquoted glob here.
  for prefs in @spotifyPreferences@; do
    [ -f "$prefs" ] || continue
    # Spotify reports this account/device as Standard-capable, whose highest
    # streaming tier is High (3); Lossless (5) is unavailable.
    update_pref "$prefs" audio.play_bitrate_enumeration 3
    update_pref "$prefs" audio.play_bitrate_non_metered_enumeration 3
    update_pref "$prefs" audio.allow_downgrade false
    # Spotify owns the platform-specific registration. Persist the supported
    # "off" preference so subsequent Spotify launches do not recreate it.
    update_pref "$prefs" app.autostart-configured true
    update_pref "$prefs" app.autostart-mode '"off"'
  done
fi
