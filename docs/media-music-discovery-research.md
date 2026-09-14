# Home music discovery and listener profiles

Reviewed: 2026-09-13. This note evaluates a self-hosted music service for a
small household. It covers local-library discovery, recommendations that can
lead outside that library, separate listener state, security, resource use, and
desktop playback. It does not measure recommendation quality or run the
services.

## Decision

The design is still the best fit found for this set of requirements, with one
important update. Use **Navidrome 0.64.0**, not 0.63.2. Keep AudioMuse-AI
3.6.0, its Navidrome plugin v10, ListenBrainz Daily Playlist Importer v6.0.0,
and Feishin 1.15.1. As of the review date those are each project's newest
tagged release, except that the importer and plugin have only a `v6.0.0` and
`v10` tag rather than a separate compatibility release for Navidrome 0.64.0.

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

## What changed since the 0.63.2 assessment

Navidrome 0.64.0 was released on 2026-09-12, one day before this review. It
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

Feishin 1.15.1 remains the best default desktop client in this comparison. Its
upstream project documents Navidrome and OpenSubsonic support, MPV playback,
lyrics, scrobble reporting, and smart-playlist editing. The 1.15.1 release
fixes a Navidrome and Subsonic scrobbling regression. It does not have a
tagged compatibility statement for Navidrome 0.64.0, so include it in the
post-upgrade smoke test and clear or resync cached server data if IDs changed.
See the [Feishin repository](https://github.com/jeffvli/feishin) and
[v1.15.1 release](https://github.com/jeffvli/feishin/releases/tag/v1.15.1).

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
| Navidrome | [v0.64.0](https://github.com/navidrome/navidrome/releases/tag/v0.64.0) | 2026-09-12 | Upgrade from 0.63.2 after a database backup and client resync plan. |
| AudioMuse-AI | [v3.6.0](https://github.com/NeptuneHub/AudioMuse-AI/releases/tag/v3.6.0) | 2026-09-11 | Keep, built from pinned source with fixed model inputs. |
| AudioMuse Navidrome plugin | [v10](https://github.com/NeptuneHub/AudioMuse-AI-NV-plugin/releases/tag/v10) | 2026-08-31 | Keep only after the restricted-library and 0.64.0 runtime tests. |
| ListenBrainz importer | [v6.0.0](https://github.com/kgarner7/navidrome-listenbrainz-daily-playlist/releases/tag/v6.0.0) | 2026-07-08 | Keep. It requires Navidrome 0.63.0 or newer. |
| Feishin | [v1.15.1](https://github.com/jeffvli/feishin/releases/tag/v1.15.1) | 2026-07-19 | Keep as the desktop default, then smoke-test after Navidrome's ID migration. |

Release dates are GitHub `published_at` values retrieved on 2026-09-13. "Latest"
means latest non-prerelease tag returned by each project's GitHub releases API
at that time, not a promise that no later release will appear.

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

The ListenBrainz importer is installed but is not enabled with fabricated
household identities. After listeners create ordinary Navidrome accounts, an
administrator configures the plugin's `users` array in Navidrome with one
Navidrome username, ListenBrainz username, and optional ListenBrainz token per
listener, grants only those users and their libraries, then enables it. Its
Daily Jams, Weekly Jams, and Weekly Exploration mappings are part of the
post-activation validation below. The resulting configuration remains in the
encrypted Navidrome database rather than Home Manager or the Nix store.

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

No server was started for this research. The conclusion follows tagged source,
release notes, and first-party API documentation. It is therefore a deployment
choice with explicit runtime tests, not proof of performance, recommendation
quality, or cross-profile authorization.
