# shellcheck shell=sh
if @pgrep@ -x Spotify >/dev/null 2>&1 || @pgrep@ -x spotify >/dev/null 2>&1; then
  echo "Skipping Spotify preferences because Spotify is running."
else
  update_preferences() (
    prefs="$1"
    temporary_prefs="$(@mktemp@ "${prefs}.tmp.XXXXXX")" || return 1
    # The subshell keeps cleanup traps and temporary variables out of activation.
    trap '@rm@ -f "$temporary_prefs"' 0

    # Keep all managed keys in one pass, retaining the first occurrence's position.
    # High (3) is this device's supported streaming tier; disable downgrades,
    # track notifications and Spotify's platform-specific autostart registration.
    # shellcheck disable=SC2016 # Awk must receive its own field and array syntax.
    @awk@ '
      BEGIN {
        FS = "="
        keys[1] = "ui.track_notifications_enabled"; values[keys[1]] = "false"
        keys[2] = "audio.play_bitrate_enumeration"; values[keys[2]] = "3"
        keys[3] = "audio.play_bitrate_non_metered_enumeration"; values[keys[3]] = "3"
        keys[4] = "audio.allow_downgrade"; values[keys[4]] = "false"
        keys[5] = "app.autostart-configured"; values[keys[5]] = "true"
        keys[6] = "app.autostart-mode"; values[keys[6]] = "\"off\""
      }
      index($0, "=") && $1 in values {
        if (!found[$1]++) print $1 "=" values[$1]
        next
      }
      { print }
      END {
        for (i = 1; i <= 6; i++) {
          if (!found[keys[i]]) print keys[i] "=" values[keys[i]]
        }
      }
    ' "$prefs" >"$temporary_prefs" || return 1
    if @cmp@ -s "$temporary_prefs" "$prefs"; then
      return 0
    else
      comparison_status=$?
      # cmp distinguishes different bytes (1) from an I/O error (2).
      [ "$comparison_status" -eq 1 ] || return "$comparison_status"
    fi
    @mv@ "$temporary_prefs" "$prefs"
  )

  # shellcheck disable=SC2043 # Nix substitutes a quoted path plus an unquoted glob here.
  for prefs in @spotifyPreferences@; do
    [ -f "$prefs" ] || continue
    update_preferences "$prefs" || return 1
  done
fi
