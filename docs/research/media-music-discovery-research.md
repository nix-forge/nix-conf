# Home music discovery and listener profiles

Reviewed: 2026-09-23. This note evaluates a self-hosted music service for a
small household. It covers local-library discovery, recommendations that can
lead outside that library, separate listener state, security, resource use, and
desktop playback. The runtime checks below confirm service startup and
listener provisioning; recommendation quality and completed acquisitions remain
unmeasured.

## Decision

The design remains the best fit found for local playback and recommendations.
Use **Navidrome 0.64.1**; its security fixes include Subsonic login throttling
and per-user library filtering. Keep AudioMuse-AI 3.6.0, its Navidrome plugin
v10, ListenBrainz Daily Playlist Importer v6.0.0, and Feishin 1.17.0 pending
the runtime checks below. These versions describe upstream availability, not
the version activated on a particular host.

This is a good division of work:

- Navidrome owns authentication, library access, playback, playlists, ratings,
  and listening history.
- AudioMuse analyzes the owned collection and supplies audio-based similarity
  to Navidrome. It does not solve listener isolation by itself.
- ListenBrainz supplies recommendations based on a listener's submitted
  history. The importer copies matches into that listener's Navidrome account.
- Feishin is the default desktop client. It speaks Navidrome and OpenSubsonic,
  so it stays on the ordinary server path instead of gaining a second account
  system.

There is a sharp boundary in this answer. This stack is strong for discovery
inside an owned collection and for importing the part of a public
recommendation list that is already owned. It is not an acquisition system.
Tracks outside the local library remain a recommendation, not playable media.

### Current update: playlist continuation and discovery outside the library

**Fact.** Navidrome can submit plays to both Last.fm and ListenBrainz from a
listener's personal settings. Last.fm uses that listener's OAuth consent;
ListenBrainz uses that listener's token. Since 0.64.0, a listener can filter
which plays leave the server while Navidrome retains the local play and
scrobble history. This gives one server-side integration for clients that
report playback to Navidrome, but it does not make the public profiles private.
See Navidrome's [scrobbling documentation](https://www.navidrome.org/docs/usage/features/scrobbling/).

**Fact.** ListenBrainz accepts authenticated listen submissions and has a
collaborative-filtering recording recommendation endpoint. It returns recording
MusicBrainz IDs and may return `204` until recommendations exist. Last.fm has
authenticated `track.scrobble`, then exposes non-authenticated
[`track.getSimilar`](https://www.last.fm/api/show/track.getSimilar) and
[`track.search`](https://www.last.fm/api/show/track.search) endpoints. These
are discovery and history services, not media-delivery APIs. See the
[ListenBrainz submission API](https://listenbrainz.readthedocs.io/en/latest/users/api/core.html#post--1-submit-listens),
[recommendation API](https://listenbrainz.readthedocs.io/en/latest/users/api/recommendation.html#cf-recommendation-user-user-name-recording-get),
and [Last.fm scrobbling specification](https://www.last.fm/api/scrobbling).

**Fact.** Finamp's 0.9.21 beta introduced an optional Radio feature that keeps
adding local-library tracks after an album, playlist, artist, genre, or queue
ends. Its Similar and Continuous modes use Jellyfin genre metadata unless the
optional AudioMuse Jellyfin plugin supplies audio-based similarity. The same
release documents that Radio does not respect Jellyfin library boundaries. The
latest stable Finamp release returned by GitHub's releases API was 0.6.27;
0.9.21 and later Radio releases are prereleases. See the
[0.9.21-beta release](https://github.com/finamp-app/finamp/releases/tag/0.9.21-beta)
and [0.6.27 stable release](https://github.com/finamp-app/finamp/releases/tag/0.6.27).

**Inference.** Keep Navidrome, Feishin, and the ListenBrainz importer as the
deployed path: they preserve the existing per-user access model and import only
locally matched recommendations. Treat Jellyfin plus Finamp Radio as a separate
client and server experiment if endless playback is a primary requirement. Do
not use it across restricted libraries until its documented boundary behavior
changes and a two-user runtime test passes.

**Fact.** Lidarr describes itself as a manager for Usenet and BitTorrent that
monitors new *albums*, and its public API has artist and album lookup/monitor
operations but only read-oriented track endpoints. Its documented manual search
chooses a release for a download client. That API shape supports album or
release acquisition, including a one-track official single, but provides no
documented task for acquiring an arbitrary recording from an album. See
[Lidarr's product documentation](https://lidarr.audio/) and its
[versioned API](https://lidarr.audio/docs/api/).

**Design for automatic acquisition.** A background bridge can read a listener's
ListenBrainz recording recommendations, skip recordings already in Navidrome,
resolve each recording to a MusicBrainz release group, and add a selected album
or single to Lidarr for its configured indexers and download client to search.
The bridge needs an explicit listener mapping, a cap on new releases per run,
deduplication by release-group ID, and a retained status for no match, no
release, download pending, import failed, and ready. It must keep the ordinary
play queue on locally available tracks while acquisitions finish. This is a
proposed integration, not functionality present in the deployed stack or an
assurance that every recommendation has a matching release at an indexer.

For catalogs that require a purchase, an authorized download can instead be
placed in a controlled import folder for tagging and scanning. Bandcamp
documents [download access](https://get.bandcamp.help/en/articles/15263100-where-do-i-download-my-purchase),
[formats](https://get.bandcamp.help/en/articles/15263234-in-which-formats-can-i-download-my-purchases),
and [terms](https://bandcamp.com/terms_of_use); its purchase path is separate
from Lidarr's indexer search.

### Runtime audit on the desktop (2026-09-23)

The active Navidrome reports 0.64.0; Navidrome, AudioMuse, Lidarr, Prowlarr,
and nix-seal services are active. The corrected `Scanner.Schedule = "@every 1h"`
configuration is deployed. The bootstrap created a managed personal listener
and updated the ListenBrainz importer. A one-time repair reset managed account
passwords with Navidrome's daemon encryption key; subsequent runs are
configured to preserve passwords and active sessions. The active run reported no
scrobbling-link errors. The identity and password are supplied through sealed
runtime credentials, so the public Nix expression does not contain the
ListenBrainz token or account name. This is a bootstrap result, not a measured
scrobble or recommendation-import test. The available unprivileged account
cannot inspect the protected library, user database, indexer configuration, or
API keys, so track count, actual searches, completed imports, and playback
remain unverified. A 0.64.1 upgrade is warranted before testing library
isolation or granting the AudioMuse plugin household access.

The desktop declaration maps the personal and Feishin listeners to the
ListenBrainz importer. The AudioMuse plugin remains disabled pending the
documented two-profile library test. The Prowlarr provider selection is stored
in a sealed runtime document. Neither a responding Prowlarr `/ping` nor that
declaration proves usable audio search results or a completed Lidarr import.
Those must be checked with actual album searches and the Lidarr queue/history.

For the requested cross-platform profile, prefer one ListenBrainz identity per
listener. Let Navidrome submit plays on behalf of clients that report playback
to Navidrome; connect any separate streaming service directly to that same
ListenBrainz identity when it supports scrobbling. Configure the importer for
that listener's Daily Jams and Weekly Exploration after the account and token
exist. Last.fm is optional; enabling it as a second history sink does not fix
the missing acquisition or playlist-continuation path. This is a deployment
recommendation based on the documented APIs above, not an observed account
configuration.

The two ListenBrainz connections need different setup: Navidrome's personal
scrobbling setting requires a ListenBrainz user token, while the playlist
importer can fetch public playlists with a mapped ListenBrainz username and no
token. The importer token is optional. Do not use an account password as either
token. A new account needs submitted listens before personal Daily Jams and
Weekly Exploration can be evaluated. See [Navidrome scrobbling](https://www.navidrome.org/docs/usage/features/scrobbling/)
and the [importer configuration](https://github.com/kgarner7/navidrome-listenbrainz-daily-playlist/blob/v6.0.0/README.md#configuration).

### Choice and required inputs

**Fact.** Feishin 1.17.0 adds a "restart queue on end" setting: when repeat is
off, it restarts from the first track instead of leaving playback at the end.
Feishin 1.12.0 also documents AutoDJ with song or album and similar or random
modes. These are client playback features; neither release documents fetching
personalized recommendations from outside the local library. See
[Feishin 1.17.0](https://github.com/jeffvli/feishin/releases/tag/v1.17.0) and
[Feishin 1.12.0](https://github.com/jeffvli/feishin/releases/tag/v1.12.0).

**Recommendation.** Keep Navidrome, AudioMuse, Feishin, and the ListenBrainz
importer as the production path. Enable Feishin's restart setting when replaying
the same playlist is acceptable, or test its AutoDJ against a restricted local
library. It provides queue continuation without a second media server or
prerelease client. Use the importer for
outside-library personalized discovery, accepting that it can play only matched
owned media. Jellyfin plus Finamp Radio provides the documented endless-queue
experience but requires a separate Jellyfin deployment and a Finamp prerelease;
its documented cross-library behavior blocks it for restricted listener
libraries.

**Current candidate for true continuation.** Music Assistant 2.10 can sit
above Navidrome through OpenSubsonic, which its documentation says it has tested
against. Its Autoplay appends similar-provider tracks, a local-library infinite
mix, or a selected playlist when a queue ends. The Automatic mode falls back to
the local library, so it provides continuous playback without an unowned-media
account. Its OpenSubsonic documentation says Navidrome needs a Last.fm API key
for similar-song Autoplay; the local infinite mix does not need that source
capability. See [Music Assistant queue settings](https://www.music-assistant.io/settings/core/),
[OpenSubsonic provider](https://www.music-assistant.io/music-providers/subsonic/),
and the [2.10 release](https://www.music-assistant.io/blog/2026/08/26/music-assistant-2-10/).

Music Assistant is the preferred pilot when continuous local playback matters.
Keep Navidrome as the music server and Feishin as a direct client during the
pilot. Add Music Assistant with a non-admin Navidrome credential, then test a
listener with a restricted library before enabling it for others. Music
Assistant supports user accounts, player restrictions, and music-source
restrictions; separate restricted Navidrome source credentials and source
assignment are necessary to avoid turning its shared controller into a path
around Navidrome library permissions. The source documents the controls but not
this exact two-library deployment, so the isolation result remains unverified.
See [Music Assistant user management](https://www.music-assistant.io/settings/user-management/).

Use Music Assistant's built-in web player for control and ordinary listening,
not as the high-resolution reference path. The web player uses Sendspin, which
is in technical preview and sends 16-bit audio to Sendspin players; higher
resolution material is converted on output. Retain direct Feishin playback for
the DAC or high-resolution test path, and inspect Music Assistant's audio
pipeline for every other player. See [Sendspin support](https://www.music-assistant.io/player-support/sendspin/).

For history, configure one reporting route for each destination. Music
Assistant offers user- and player-scoped Last.fm, ListenBrainz, and Subsonic
scrobblers, but its documentation warns that a music source can also submit a
scrobble and cause duplicates. Prefer Navidrome's existing per-user external
scrobbling for direct Feishin playback. Enable a Music Assistant external
scrobbler only after disabling the overlapping Navidrome route for that
listener and testing the resulting history. See the
[Last.fm plugin](https://www.music-assistant.io/plugins/lastfm_scrobble/),
[ListenBrainz plugin](https://www.music-assistant.io/plugins/listenbrainz_scrobble/),
and [Subsonic plugin](https://www.music-assistant.io/plugins/subsonic_scrobble/).

Outside-library playback remains optional. Music Assistant can use a connected
streaming provider for recommendations and Endless Mix; for example, its Tidal
provider requires an OAuth sign-in and a paid subscription. Without such an
account, the documented fallback is local media. Do not assume that a streaming
subscription or its credentials exist. See the
[Tidal provider documentation](https://www.music-assistant.io/music-providers/tidal/).

The requested automatic Lidarr/Prowlarr acquisition should begin as a bounded
pilot. Run a dry-run against a real ListenBrainz playlist, then permit a small
number of new release groups per day and inspect Lidarr's search, download,
import, and failure history. Keep already-owned recordings and monitored
release groups out of the queue. A streaming source can play a recommended
track while its owned copy is still pending; a local-only queue continues with
available tracks. An indexer search may fail to find a suitable release.

One direct candidate is the third-party
[listenbrainz-lidarr-sync](https://github.com/cofob/listenbrainz-lidarr-sync)
project. It resolves ListenBrainz playlist recordings to MusicBrainz release
groups, marks matching Lidarr albums wanted, and can optionally request
`AlbumSearch`. It requires Lidarr API access and defaults both automatic search
settings to false. It has no tagged release in its GitHub release area, so use
its dry-run mode and pin a reviewed revision before treating it as an automated
bridge. It still selects albums or release groups, not individual tracks, and
does not establish that a result is permitted to download.

### No-paid-streaming decision: local playback and acquisition quality

**Recommendation.** Use Music Assistant above Navidrome with the local
infinite-mix Autoplay setting for uninterrupted playback from the owned
collection. Keep ListenBrainz optional and per listener: it supplies
personalized discovery from submitted history but is not needed to keep local
playback running. This is the most capable documented no-paid-service path in
this comparison. It does not turn an outside-library recommendation into an
available local file.

DroppedNeedle can request a whole album or an individual track. Its built-in
Free Music source draws from Internet Archive recordings marked Creative
Commons or public domain, but that catalogue will not cover arbitrary
commercial recommendations. DroppedNeedle has its own download and library
engine rather than using Lidarr as the owner of requests. Its 2.15.0 release
is recent; test it against a disposable copy of a library before deciding
whether the single-track feature is worth a second acquisition system.
See its [README](https://github.com/DroppedNeedle/DroppedNeedle) and
[v2.15.0 release](https://github.com/DroppedNeedle/DroppedNeedle/releases/tag/v2.15.0).

DroppedNeedle can also control an operator-provided slskd client or
SABnzbd/Newznab sources. Tubifarry 2.2.0.5 likewise connects Lidarr to slskd
and can fetch audio from YouTube. Soularr 1.2.2 reads Lidarr's wanted albums
and artists through slskd, then asks Lidarr to import completed files. These
tools can improve coverage, but a search match does not verify the recording
or audio quality. Prefer a FLAC quality floor, quarantine ambiguous matches,
and inspect imported tags, duration, and codec before exposing the file in
Navidrome. Tubifarry's FFmpeg conversion cannot restore quality absent from a
lossy source, so its YouTube path is a poor primary source for a lossless
library. Review distribution rights for any new source independently. See
[Tubifarry](https://github.com/TypNull/Tubifarry),
[Tubifarry v2.2.0.5](https://github.com/TypNull/Tubifarry/releases/tag/v2.2.0.5),
[Soularr](https://github.com/mrusse/soularr), and
[Soularr v1.2.2](https://github.com/mrusse/soularr/releases/tag/v1.2.2).

Tubifarry cannot currently be tested on the running desktop: version 2.2.0.2
requires Lidarr 3.1.3.0 and the current 2.2.0.5 release requires Lidarr
3.1.5.0, while the running Lidarr reports 3.1.0.4875. Upgrade Lidarr and test
the plugin on a copy of the library before installing it. See the
[2.2.0.2 release](https://github.com/TypNull/Tubifarry/releases/tag/v2.2.0.2)
and [2.2.0.5 release](https://github.com/TypNull/Tubifarry/releases/tag/v2.2.0.5).

The existing Mullvad route is a separate slskd deployment risk. Mullvad states
that it no longer provides port forwarding. slskd documents that forwarding its
listen port provides full connectivity, and lists poor search results and an
inability to browse some users as symptoms of a misconfigured port. Therefore
an slskd deployment through that route is expected to have incomplete network
reachability; this is an inference from the two upstream documents, not a
runtime test of this host. See Mullvad's
[port-forwarding policy](https://mullvad.net/en/help/search?q=port+forward)
and [slskd connection documentation](https://github.com/slskd/slskd/blob/master/docs/config.md).

**Selected client.** Use slskd as the server-side Soulseek client, with Soularr
as a later Lidarr integration if the existing indexers cannot find music. Its
API can support unattended searches and transfers, unlike a desktop-only
client. Keep its account credentials and API key in nix-seal, and require a
real search, transfer, and import test before enabling automatic requests from
Soularr. The current Mullvad route has no port forwarding, so peer reachability
may be incomplete. See [slskd's configuration](https://github.com/slskd/slskd/blob/master/docs/config.md)
and [Soularr's required API](https://github.com/mrusse/soularr/blob/main/README.md).

Tagging is the quality-control gate after import. MusicBrainz Picard can scan
files with AcoustID and flags ambiguous track matches for human verification.
Beets 2.14.1 can batch-tag through MusicBrainz and Chromaprint/AcoustID, but
its import can write tags, move, or copy files; use a backup and review mode
before any bulk action. Neither tool proves an audio file's provenance or
restores audio quality. See [Picard matching](https://picard-docs.musicbrainz.org/en/latest/config/options_matching.html),
[Picard fingerprinting](https://picard-docs.musicbrainz.org/en/latest/config/options_fingerprinting.html),
[beets autotagging](https://beets.readthedocs.io/en/latest/guides/tagger.html),
[beets import safety](https://beets.readthedocs.io/en/stable/guides/main.html),
and [beets v2.14.1](https://github.com/beetbox/beets/releases/tag/v2.14.1).

The current blockers for acquisition automation are a verified music search and
import through the configured Lidarr indexers, a daily request and storage cap,
and a quarantine rule for ambiguous matches. Automatic release addition is the
selected behavior; Lidarr still acquires releases rather than arbitrary album
tracks. Keep download credentials in protected runtime storage. The optional
slskd client connected and logged in on 2026-09-23 using sealed runtime
credentials. A real search, transfer, and Lidarr import remain unverified;
Soularr should not start automatic requests before those checks.

For playlist continuation, Music Assistant's local infinite mix is the selected
no-subscription pilot. It still needs a dedicated non-admin Navidrome source
account, player setup, and an access-control test before it can take over any
listener's ordinary queue. The active Feishin client and Navidrome server do
not yet provide the requested after-playlist recommendation queue through this
configuration.

## What changed since the 0.63.2 assessment

At the prior 2026-09-13 review, Navidrome 0.64.0 had just been released. It
supersedes 0.63.2 and fixes SQL injection in a Native API filter, a share-owner
IDOR, plugin HTTP and WebSocket SSRF bypasses, a login rate-limit bypass, and
an image-decoding memory-exhaustion path. It also makes playlist import faster
on large libraries, adds per-user scrobble filters and history API support,
and keeps playlist stars and ratings per user. The full release record is
[Navidrome v0.64.0](https://github.com/navidrome/navidrome/releases/tag/v0.64.0).

The 0.64.0 upgrade is a database migration, not a routine container swap. It
re-encodes all internal IDs. Back up Navidrome's database first, then have
clients with offline or cached item IDs resynchronize. That is especially
relevant to a desktop or mobile client after the update.

It also changes the plugin network contract. Extism's direct HTTP client is
disabled. Plugins must use Navidrome's host HTTP service. Named hosts resolving
to loopback or private addresses are blocked unless their IP address or CIDR is
declared in `requiredHosts`; a bare `"*"` remains an allowed alternative. This
hardens Navidrome, but it makes an untested plugin deployment risky.

The AudioMuse v10 source already calls `host.HTTPSend`, so it has made the
required API migration. Its manifest declares `requiredHosts: ["*"]`, which
means the 0.64.0 block should not stop an internal AudioMuse call. The wildcard
is broader than this service needs, though. Treat the v10 release as
source-compatible rather than runtime-verified, and do not install another
plugin with that permission casually. See the tagged
[AudioMuse v10 manifest](https://github.com/NeptuneHub/AudioMuse-AI-NV-plugin/blob/v10/manifest.json)
and [HTTP implementation](https://github.com/NeptuneHub/AudioMuse-AI-NV-plugin/blob/v10/audiomuse_api.go).

The ListenBrainz importer v6.0.0 requires Navidrome 0.63.0 or newer and uses
the native matcher API. Its release does not name 0.64.0, but the documented
minimum includes the new target version. It requests only the ListenBrainz
host plus library, matcher, scheduler, task queue, user, and Subsonic API
permissions. This is a narrower network grant than AudioMuse's. See
[Importer v6.0.0](https://github.com/kgarner7/navidrome-listenbrainz-daily-playlist/releases/tag/v6.0.0)
and its [tagged manifest](https://github.com/kgarner7/navidrome-listenbrainz-daily-playlist/blob/v6.0.0/manifest.json).

## Why the stack still fits

### Listener profiles

Navidrome has separate users, per-user playlists and ratings, and library
access control. A user can have access to selected libraries, while an admin
can access all libraries. Use a non-admin account for every listener if
library separation is meant to protect privacy. Its documented multi-library
rules are the identity boundary for this design. See
[multi-library access](https://www.navidrome.org/docs/usage/features/multi-library/)
and [scrobbling](https://www.navidrome.org/docs/usage/features/scrobbling/).

Each listener should use a separate ListenBrainz account and token. Navidrome
records that token in the user's personal settings, while the ListenBrainz
base URL is server-wide. One Navidrome instance therefore cannot route one
user to public ListenBrainz and another to a different private endpoint. This
is a deliberate privacy choice per listener, not a global switch. The relevant
server behavior is in Navidrome's [scrobbling documentation](https://www.navidrome.org/docs/usage/features/scrobbling/).

The importer has an explicit array of mappings from Navidrome usernames to
ListenBrainz usernames and optional tokens. It imports Daily Jams, Weekly
Jams, Weekly Exploration, or chosen ListenBrainz playlists into the mapped
Navidrome account. It also creates playlists through Navidrome's API on behalf
of that user. That makes it the cleanest bridge for multiple listener
profiles. The [v6.0.0 manifest](https://github.com/kgarner7/navidrome-listenbrainz-daily-playlist/blob/v6.0.0/manifest.json)
is the source for the mapping, permissions, and schedule.

AudioMuse has a weaker identity story. The v10 Navidrome plugin holds one
shared AudioMuse URL and optional bearer token. Its similarity requests pass a
track or artist identifier, but no Navidrome user identity. Do not assume the
plugin's Instant Mix results enforce a listener's library boundary merely
because Navidrome does. Run a restricted-library test before exposing that
feature to more than one profile. Use Navidrome permissions and the imported
ListenBrainz playlists as the privacy boundary. Keep the AudioMuse web UI
administrator-only until its separate account and authorization behavior has
been tested. The evidence is visible in the tagged
[plugin configuration](https://github.com/NeptuneHub/AudioMuse-AI-NV-plugin/blob/v10/manifest.json)
and [similar-track request](https://github.com/NeptuneHub/AudioMuse-AI-NV-plugin/blob/v10/main.go).

### Discovery quality

AudioMuse 3.6.0 combines audio embeddings, lyrics and text embeddings, mood
analysis, clustering, similarity indexes, paths, and a music map. Its worker
does analysis and index construction; the web process answers similarity
queries. The index is disk-paged and memory-mapped. This makes it a credible
local-library recommender without assuming perfect genre metadata. These are
upstream design claims, not a measured ranking of its recommendations. See the
tagged [architecture](https://github.com/NeptuneHub/AudioMuse-AI/blob/v3.6.0/docs/ARCHITECTURE.md)
and [algorithm documentation](https://github.com/NeptuneHub/AudioMuse-AI/blob/v3.6.0/docs/ALGORITHM.md).

AudioMuse 3.6.0 added an optional Neural Fingerprint model for searching a
recorded or uploaded clip against the local library. It is disabled by default
and fingerprints are created in a later analysis run. That is useful, but it
is an extra analysis cost rather than a reason to enable it on day one. The
[v3.6.0 release](https://github.com/NeptuneHub/AudioMuse-AI/releases/tag/v3.6.0)
also records queue cancellation and cleanup changes.

ListenBrainz adds a different kind of discovery: collaborative-filtered
recommendations and generated playlists based on the user's submitted listens.
Its data jobs are scheduled rather than real time. The public service is a
privacy tradeoff because listening data feeds a public project. A listener who
does not accept that tradeoff can keep Navidrome history and use AudioMuse only.
See ListenBrainz's first-party [data update schedule](https://github.com/metabrainz/listenbrainz-server/blob/master/docs/general/data-update-intervals.rst)
and [recommendation API](https://listenbrainz.readthedocs.io/en/latest/users/api/core.html#cf-recommendation-user-user-name-recording-get).

Matching determines whether ListenBrainz recommendations become usable local
playlists. Importer v6 uses Navidrome's matcher API and asks for library access
to match MusicBrainz tracks. Tagging recordings and artists with MusicBrainz
IDs remains the practical prerequisite. Start with imported playlists. Its
experimental local generator asks ListenBrainz for up to 1,000 recording
recommendations, then performs local matching, so measure it before scheduling
it for every listener.

### Resources and topology

AudioMuse 3.6.0 uses PostgreSQL as both persistent store and task queue. The
tagged architecture says there is no separate broker. Its 3.6.0 parameter
reference says that, after the setup transition, PostgreSQL and `TZ` are the
environment settings that still must be supplied; the browser setup stores
other settings in its database. Earlier claims that a Redis service is required
are not supported by this version's source. See the [architecture](https://github.com/NeptuneHub/AudioMuse-AI/blob/v3.6.0/docs/ARCHITECTURE.md)
and [parameters](https://github.com/NeptuneHub/AudioMuse-AI/blob/v3.6.0/docs/PARAMETERS.md).

Run one CPU worker initially. The first analysis, optional lyric transcription,
clustering, and optional Neural Fingerprint work are the expensive operations.
Extra workers are a batch-time choice, not a permanent requirement. Disable
external lyric providers, automatic speech recognition, cloud language-model
providers, and Neural Fingerprint unless a listener needs each feature. The
same parameter reference documents their defaults and controls.

Expose only Navidrome's authenticated HTTPS endpoint to clients. Keep
PostgreSQL on its local Unix socket and AudioMuse's web/API process on
loopback. The native worker shares the service's local process group and does
not need a network listener. The AudioMuse plugin needs a private loopback
route from Navidrome to AudioMuse, but that is not a reason to publish
AudioMuse. Give AudioMuse a dedicated, non-admin Navidrome account with access
only to the library it must analyze.

Set AudioMuse authentication on and retain a fixed JWT secret, web credential,
and API token. The tagged parameter reference names `AUTH_ENABLED`,
`AUDIOMUSE_USER`, `AUDIOMUSE_PASSWORD`, `API_TOKEN`, and `JWT_SECRET`. Store
deployment secrets in protected runtime files. The plugin's bearer token is
entered through Navidrome's plugin configuration, so its storage and backups
need the same treatment as the Navidrome database.

For Navidrome, run as a non-root numeric user, set `EnforceNonRootUser=true`,
mount the music tree read-only, restrict the writable data directory to the
service user, limit transcodes, and avoid unauthenticated shares. Do not use
external authentication unless the reverse proxy is the only path to
Navidrome and trusted-source configuration names only that proxy. See
[Navidrome security guidance](https://www.navidrome.org/docs/usage/admin/security/),
[external authentication](https://www.navidrome.org/docs/usage/integration/authentication/),
and [configuration options](https://www.navidrome.org/docs/usage/configuration/options/).

### Client choice

Feishin 1.17.0 remains the best default desktop client in this comparison. Its
upstream project documents Navidrome and OpenSubsonic support, MPV playback,
lyrics, scrobble reporting, and smart-playlist editing. Its 1.15.1 release
fixes a Navidrome and Subsonic scrobbling regression. It does not have a
tagged compatibility statement for Navidrome 0.64.0, so include it in the
post-upgrade smoke test and clear or resync cached server data if IDs changed.
See the [Feishin repository](https://github.com/jeffvli/feishin) and
[v1.15.1 release](https://github.com/jeffvli/feishin/releases/tag/v1.15.1),
and [v1.17.0 release](https://github.com/jeffvli/feishin/releases/tag/v1.17.0).

Navidrome 0.64.0 also has an experimental Jellyfin Music API. It is not needed
for Feishin and should stay disabled in the first deployment. A new API and
its public-user option add review work without answering the stated discovery
requirements.

## Alternatives rejected for the first deployment

Koito and Maloja record and display self-hosted listening history. They do not
replace the combination of Navidrome user access, audio-based local discovery,
and imported per-user recommendation playlists. Maloja explicitly positions
itself as a personal statistics database and excludes radio and
recommendations. See the [Maloja README](https://github.com/krateng/maloja).

RompR is an MPD or Mopidy client, not a replacement for the server and
discovery arrangement. Its own Mopidy guide says building a collection through
Mopidy's Subsonic backend is slow. See [RompR and Mopidy](https://fatg3erman.github.io/RompR/Rompr-And-Mopidy.html).

Self-hosting all of ListenBrainz is disproportionate for this job. Its source
tree includes PostgreSQL, TimescaleDB, CouchDB, Spark, and batch jobs. Use the
public service only for listeners who consent to it. See the
[ListenBrainz server repository](https://github.com/metabrainz/listenbrainz-server).

## Release and compatibility ledger

| Component | Latest tagged release checked | Publication date | Decision |
| --- | --- | --- | --- |
| Navidrome | [v0.64.1](https://github.com/navidrome/navidrome/releases/tag/v0.64.1) | 2026-09-21 | Upgrade the running 0.64.0 after a database backup and plugin/client smoke test. |
| AudioMuse-AI | [v3.6.0](https://github.com/NeptuneHub/AudioMuse-AI/releases/tag/v3.6.0) | 2026-09-11 | Keep, built from pinned source with fixed model inputs. |
| AudioMuse Navidrome plugin | [v10](https://github.com/NeptuneHub/AudioMuse-AI-NV-plugin/releases/tag/v10) | 2026-08-31 | Keep only after the restricted-library and 0.64.0 runtime tests. |
| ListenBrainz importer | [v6.0.0](https://github.com/kgarner7/navidrome-listenbrainz-daily-playlist/releases/tag/v6.0.0) | 2026-07-08 | Keep. It requires Navidrome 0.63.0 or newer. |
| Feishin | [v1.17.0](https://github.com/jeffvli/feishin/releases/tag/v1.17.0) | 2026-09-15 | Keep as the desktop default, then smoke-test after Navidrome's ID migration. |
| Music Assistant | [2.10](https://www.music-assistant.io/blog/2026/08/26/music-assistant-2-10/) | 2026-08-26 | Pilot above Navidrome for Autoplay; verify source and listener isolation. |
| Finamp | [0.6.27 stable](https://github.com/finamp-app/finamp/releases/tag/0.6.27); [1.0.1-beta](https://github.com/finamp-app/finamp/releases/tag/1.0.1-beta) | 2025-01-25; 2026-09-02 | Do not deploy for Radio until a stable release and restricted-library test. |
| DroppedNeedle | [v2.15.0](https://github.com/DroppedNeedle/DroppedNeedle/releases/tag/v2.15.0) | 2026-09-20 | Evaluate only as a Lidarr replacement, in a disposable library copy. |
| Tubifarry | [v2.2.0.5](https://github.com/TypNull/Tubifarry/releases/tag/v2.2.0.5) | 2026-09-09 | Requires a Lidarr upgrade; evaluate its slskd path with a FLAC profile. |
| Soularr | [v1.2.2](https://github.com/mrusse/soularr/releases/tag/v1.2.2) | 2026-04-28 | Candidate slskd path for Lidarr albums; no documented single-track path. |
| beets | [v2.14.1](https://github.com/beetbox/beets/releases/tag/v2.14.1) | 2026-09-17 | Use as an optional batch tagging tool with preview and backup. |
| MusicBrainz Picard | [2.13.3](https://github.com/metabrainz/picard/releases/tag/release-2.13.3) | 2025-02-17 | Use for manual review of ambiguous or important releases. |

Release dates are GitHub `published_at` values retrieved on 2026-09-23. "Latest"
means latest non-prerelease tag returned by each applicable project's GitHub
releases API at that time, not a promise that no later release will appear.

## Repository implementation

The desktop configuration applies a temporary Navidrome 0.64.0 package override
only while the pinned Nixpkgs package is older. The override uses Go 1.27, as
required by the release, and stops applying when Nixpkgs supplies 0.64.0 or a
newer version. A one-time pre-start backup copies the existing SQLite database
before the 0.64.0 migration.

The AudioMuse plugin override selects v10 and patches its HTTP permission from
`"*"` to `"127.0.0.1"`, matching the configured API URL. Navidrome and
AudioMuse both listen only on loopback. Caddy exposes the stable desktop name
and configured LAN address on HTTPS port 4534 with its internal certificate
authority. Clients must trust Caddy's local root certificate before login.
Caddy does not write an access log for this endpoint because some Subsonic
clients put authentication fields in request URLs.
The shared homelab nginx ingress also serves Navidrome on port 443 with the
host's ACME certificate and disabled access logging. The port 4534 endpoint
remains for existing clients until their saved URLs and trust stores migrate.

AudioMuse is built from tagged source with separately fixed model inputs and
runs as a hardened native systemd service against Nixpkgs PostgreSQL. PostgreSQL
uses its local Unix socket; neither it nor AudioMuse publishes a LAN port. Two
sealed environment files separate the AudioMuse and Navidrome credentials.
A root-only one-shot projects just the AudioMuse API token into a systemd
credential for the unprivileged bootstrap; the bootstrap does not receive the
AudioMuse web password or JWT secret, and the Navidrome daemon does not receive
bootstrap account passwords. The services have CPU, memory, task, and
filesystem limits. Navidrome limits concurrent transcodes globally and per
user. Native Navidrome backups and daily PostgreSQL dumps go to the encrypted
data volume.

The bootstrap creates one Navidrome administrator and a non-admin AudioMuse
service account without putting their passwords in the Nix store. Household
listeners remain ordinary Navidrome accounts. Each person can opt into a
separate ListenBrainz account and map it through the importer plugin. Feishin is
installed for both desktop home profiles, but no server credential is written
to Home Manager configuration. The AudioMuse plugin is initially restricted to
the service account and disabled. After the two-profile isolation test below
passes, create the root-owned, world-readable empty file
`/srv/data/media/.services/music-discovery/backups/.audiomuse-household-approved`
and restart `music-discovery-bootstrap.service`. The bootstrap then grants
household access and enables the plugin. Removing the marker makes the next
bootstrap restrict and disable it again.

The bootstrap now creates the managed Navidrome listener when absent, using a
separate sealed password. It links that listener and the existing Feishin
listener to the same ListenBrainz account through Navidrome's authenticated
per-user API. It configures the importer for Daily Jams, Weekly Jams, and
Weekly Exploration in both profiles. The public account name and token come
from a nix-seal ciphertext and enter a private runtime configuration file, not
a Nix store JSON file. An existing listener with a different password cannot
be linked automatically; the bootstrap reports that case without replacing the
user's password. Activation and an import test are still required before
calling this connection operational. The [Navidrome 0.64.0 ListenBrainz route](https://github.com/navidrome/navidrome/blob/v0.64.0/adapters/listenbrainz/auth_router.go)
validates and saves the token for the authenticated user.

### Importer permission correction (2026-09-24)

The running importer logged a failed initial fetch and a failed scheduled fetch:
its Subsonic API call said the mapped listener was not authorized for the
plugin. Navidrome 0.64.0 and 0.64.1 accept usernames in `plugin edit --users`
but store those strings as the allowed entries; the plugin's Subsonic API host
function compares them with the user's internal ID. The desktop bootstrap now
resolves the two managed usernames to IDs before applying the restricted plugin
scope, and stops if an account is missing or ambiguous. This avoids granting
the plugin access to every user. The corrected configuration has built but
still needs activation and an import smoke test. See the [CLI conversion](https://github.com/navidrome/navidrome/blob/v0.64.1/cmd/plugin.go),
[plugin access check](https://github.com/navidrome/navidrome/blob/v0.64.1/plugins/host_subsonicapi.go),
and [local bootstrap](../../hosts/nixos/desktop/local/homelab/music/discovery.nix).

## Required validation before calling it deployed

- Back up Navidrome, upgrade a copy to 0.64.0, and verify login, scans,
  playlists, scrobbling, plugin loading, and Feishin after cached IDs are
  refreshed.
- Temporarily grant the AudioMuse plugin access to two non-admin test users
  with separate libraries, then ask for similar tracks as each user. Confirm
  that no result, stream, playlist, history, rating, or recommendation crosses
  the library boundary before creating the household approval marker.
- Verify AudioMuse v10 can reach its internal API under Navidrome 0.64.0. Record
  the plugin's approved `requiredHosts` behavior and reject unexpected outbound
  requests.
- Import Daily Jams, Weekly Jams, and Weekly Exploration for two separate
  ListenBrainz users. Measure MusicBrainz match rate and confirm the playlists
  land only in the configured Navidrome account.
- Measure first analysis duration, peak memory, PostgreSQL size, and incremental
  scan cost with one worker before enabling transcription, local generation, or
  more workers.

The 2026-09-23 audit checked service state, unauthenticated health endpoints,
and Navidrome's startup logs without starting or restarting a server. The
remaining runtime checks are necessary before claiming recommendation quality,
cross-profile authorization, or completed acquisition.
