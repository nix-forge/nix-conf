# shellcheck shell=sh
spotify_app=@spotifyApp@

if [ -d "$spotify_app" ]; then
  @chmod@ -R u+w "$spotify_app"
  @xattr@ -cr "$spotify_app" 2>/dev/null || true
  if @codesign@ --force --deep --options runtime --entitlements "@spotifyEntitlements@" --sign - "$spotify_app" &&
    @codesign@ --verify --deep --strict --verbose=2 "$spotify_app"; then
    # Re-register the copied bundle so Dock and bundle-ID launches do not
    # resolve a stale Spotify app that Spicetify created in a build temp dir.
    @lsregister@ -f "$spotify_app"
  else
    echo "Warning: Spotify app is incomplete or could not be signed; continuing Home Manager activation." >&2
  fi
fi
