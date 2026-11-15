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
    @awk@ -f @preferenceUpdater@ @managedPreferences@ "$prefs" >"$temporary_prefs" || return 1
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
