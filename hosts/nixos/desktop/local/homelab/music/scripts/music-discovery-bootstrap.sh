# shellcheck shell=bash
set -eu

curl --fail --silent --show-error --output /dev/null \
  --retry 20 --retry-delay 2 --retry-connrefused --retry-all-errors \
  --connect-timeout 2 --max-time 3 \
  http://127.0.0.1:@toString_navidromePort@/ping

users_json="$(navidrome --configfile @navidromeConfig@ user list --format json)"
has_user() {
  jq --exit-status --arg user "$1" \
    'map(.userName // .username // .UserName) | index($user) != null' \
    <<<"$users_json" >/dev/null
}
create_user() {
  local username="$1"
  local password="$2"
  local role="$3"
  MUSIC_DISCOVERY_USERNAME="$username" \
    MUSIC_DISCOVERY_PASSWORD="$password" \
    MUSIC_DISCOVERY_ROLE="$role" \
    expect @pkgs_writeText_create_navidrome_user_expect_set_timeout_30_l@
}
admin_user="$(cat "$CREDENTIALS_DIRECTORY/navidrome-admin-username")"
service_user="$(cat "$CREDENTIALS_DIRECTORY/navidrome-service-username")"
feishin_user="$(cat "$CREDENTIALS_DIRECTORY/feishin-listener-username")"
export NAVIDROME_ADMIN_USERNAME="$admin_user"
if ! has_user "$admin_user"; then
  create_user "$admin_user" "$NAVIDROME_ADMIN_PASSWORD" admin
  users_json="$(navidrome --configfile @navidromeConfig@ user list --format json)"
fi
if ! has_user "$service_user"; then
  create_user "$service_user" "$NAVIDROME_SERVICE_PASSWORD" regular
fi
if ! has_user "$feishin_user"; then
  listener_password="$(cat "$CREDENTIALS_DIRECTORY/feishin-listener-password")"
  create_user "$feishin_user" "$listener_password" regular
fi

listenbrainz_identity="$CREDENTIALS_DIRECTORY/listenbrainz-identity"
listenbrainz_user="$(jq --exit-status --raw-output '.navidromeUsername | select(type == "string" and length > 0)' "$listenbrainz_identity")"
listenbrainz_password="$CREDENTIALS_DIRECTORY/listenbrainz-listener-password"
if ! has_user "$listenbrainz_user"; then
  listener_password="$(cat "$listenbrainz_password")"
  create_user "$listenbrainz_user" "$listener_password" regular
fi
users_json="$(navidrome --configfile @navidromeConfig@ user list --format json)"
plugin_user_ids="$(printf '%s' "$users_json" | @lib_getExe_resolvePluginUserIds@ "$listenbrainz_user" "$feishin_user")"
if ! @linkListenBrainz@ "$listenbrainz_identity" "$listenbrainz_password"; then
  echo "ListenBrainz scrobbling could not be linked; check the managed listener credentials" >&2
fi
if ! @linkListenBrainz@ "$listenbrainz_identity" \
  "$CREDENTIALS_DIRECTORY/feishin-listener-password" "$feishin_user"; then
  echo "ListenBrainz scrobbling could not be linked for the Feishin listener" >&2
fi

navidrome --configfile @navidromeConfig@ plugin rescan
@configureLyricsPlugin@ @lyricsPluginConfig@
# Render the account mapping only in the private runtime directory.
listenbrainz_config="$RUNTIME_DIRECTORY/listenbrainz-plugin.json"
jq --null-input --arg listener "$feishin_user" --slurpfile identity "$listenbrainz_identity" '
  $identity[0] as $account |
  if ($account.listenbrainzUsername | type == "string" and length > 0)
    and ($account.token | type == "string" and length > 0) then
    {
      schedule: 8,
      checkOnStartup: true,
      users: ([$account.navidromeUsername, $listener] | map({
        username: .,
        lbzUsername: $account.listenbrainzUsername,
        lbzToken: $account.token,
        generatePlaylist: false,
        ratings: ["0", "1", "2", "3", "4", "5"],
        sources: [
          {sourcePatch: "daily-jams", playlistName: "ListenBrainz Daily Jams"},
          {sourcePatch: "weekly-jams", playlistName: "ListenBrainz Weekly Jams"},
          {sourcePatch: "weekly-exploration", playlistName: "ListenBrainz Weekly Exploration"}
        ]
      }))
    }
  else error("ListenBrainz account identity is incomplete") end
' >"$listenbrainz_config"
if has_user "$listenbrainz_user"; then
  navidrome --configfile @navidromeConfig@ plugin edit listenbrainz-daily-playlist \
    --config-file "$listenbrainz_config" --users "$plugin_user_ids" --all-libraries --no-write-access
  navidrome --configfile @navidromeConfig@ plugin enable listenbrainz-daily-playlist
else
  echo "ListenBrainz importer awaits its configured Navidrome user"
fi
rm -f "$listenbrainz_config"

# The plugin runs inside Navidrome, so loopback reaches the only
# published AudioMuse port. Its bearer token never enters the Nix store.
plugin_config="$RUNTIME_DIRECTORY/audiomuse-plugin.json"
jq --null-input \
  --arg apiUrl "http://127.0.0.1:@toString_audioMusePort@" \
  --rawfile apiToken "$CREDENTIALS_DIRECTORY/audiomuse-api-token" \
  '{
    apiUrl: $apiUrl,
    apiToken: ($apiToken | sub("\n+$"; "")),
    artistSimilarCount: 20,
    instantMixSource: "similarSong",
    eliminateDuplicates: true,
    radiusSimilarity: true
  }' >"$plugin_config"
navidrome --configfile @navidromeConfig@ plugin edit audiomuseai \
  --config-file "$plugin_config" --users "$service_user" --all-libraries --no-write-access
if [ -r @lib_escapeShellArg_audioMuseHouseholdApproval@ ]; then
  navidrome --configfile @navidromeConfig@ plugin edit audiomuseai \
    --all-users --all-libraries --no-write-access
  navidrome --configfile @navidromeConfig@ plugin enable audiomuseai
else
  navidrome --configfile @navidromeConfig@ plugin disable audiomuseai
  echo "AudioMuse plugin remains disabled pending household isolation approval"
fi
rm -f "$plugin_config"
