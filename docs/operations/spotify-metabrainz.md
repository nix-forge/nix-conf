# Spotify and MetaBrainz

The shared Spotify home module installs a small Spicetify `MetaBrainz` track
menu on Linux and macOS. Right-click a Spotify track to search its recording,
release, or artist on MusicBrainz. These are searches based on Spotify's names,
not asserted MusicBrainz matches. Review the result before editing MusicBrainz
or using its identifiers with Cover Art Archive and CritiqueBrainz. The menu
also opens ListenBrainz's connected-services settings.

For listening history, connect the Spotify account to the same ListenBrainz
account used by the Navidrome listener. Open
[ListenBrainz connected services](https://listenbrainz.org/settings/music-services/details/),
sign in, and select Spotify's "Record listening history" or "Activate both
features" option there. This connection follows the Spotify account across
the Linux desktop, the Mac, and other Spotify clients. The playback option also
allows Spotify Premium users to play matched music in ListenBrainz's BrainzPlayer.
It does not require a Spotify token in Nix or a second client-side scrobbler.
After playing a track, allow several minutes for it to appear in ListenBrainz.
Avoid another Spotify scrobbler for the same account to prevent duplicate
submissions.

Check completed plays on `https://listenbrainz.org/user/<USER>/`, using the
ListenBrainz account linked to Navidrome. The general `/feed/` page is not that
account's listening history. For a direct check, request
`https://api.listenbrainz.org/1/user/<USER>/listens?count=20`. The response's
`track_metadata.additional_info.submission_client` identifies Navidrome
submissions; a missing Spotify listen after several minutes calls for checking
the Spotify connection under ListenBrainz connected services and confirming that
the connected Spotify and ListenBrainz accounts are the intended ones.
The separate "Import listens" page accepts a downloaded Spotify data archive
for past history; uploading there is not the live Spotify connection.

Spotify now requires reconnecting the ListenBrainz authorization every six
months. ListenBrainz says it sends reminders before expiry. The connection and
playback need an account-level runtime check; a Nix evaluation cannot prove
either. ListenBrainz listening data is public and released under CC0, so make
that choice before authorizing the history import.

ListenBrainz matches incoming listens against MusicBrainz and uses those matches
for recommendations and playlists. The existing Navidrome importer can copy
matched Daily Jams and Weekly Exploration tracks into the local listener's
library. Its separate Navidrome scrobbling link covers Feishin and other clients
that play through Navidrome. Spotify's connection covers Spotify playback.

Sources: [Spicetify extension API](https://spicetify.app/docs/development/extensions),
[MusicBrainz search](https://musicbrainz.org/search),
[ListenBrainz connected-services settings](https://github.com/metabrainz/listenbrainz-server/blob/master/frontend/js/src/settings/music-services/details/MusicServices.tsx),
[ListenBrainz data update schedule](https://github.com/metabrainz/listenbrainz-server/blob/master/docs/general/data-update-intervals.rst),
[ListenBrainz listen API](https://listenbrainz.readthedocs.io/en/latest/users/api/core.html),
[ListenBrainz Spotify reconnection release](https://github.com/metabrainz/listenbrainz-server/releases/tag/v-2026-07-20.0),
and [ListenBrainz data policy](https://listenbrainz.org/download/).
