# Shared music metadata, lyrics, and artwork

Reviewed: 2026-10-03. Scope: Navidrome 0.64.2, Jellyfin 12.1 at runtime with the compatible library API,
Lidarr source revision `da7b4dfb1a9e7e1d6625c2dbc3fff96971ab26bd`,
Aurral 2.9.1 with the repository's existing metadata patches, and AudioMuse-AI
3.6.0 revision `31239fa986afb91a15e039e1a9a64ed5a2d6fa12`.
The implementation and runtime evidence are recorded below.

## Answer

Use the shared music files as the interchange boundary: accurate standard tags
and MusicBrainz recording/release identifiers, a curated album `cover.jpg`, and
UTF-8 lyrics beside each track with the same filename stem. Keep playback
servers read-only. Use one bounded maintenance writer for missing synchronized
lyrics, leaving all existing sidecars and audio files untouched. Navidrome's
existing plugin remains useful as an on-demand fallback; it does not make its
responses available to the separate Jellyfin server.

Both servers support LRC, ELRC and plain text; other structured sidecars
should be retained without pretending every client can render word timing.
A missing exact recording match is preferable to persisting another recording's
lyrics. Matching duration and names improves accuracy but does not prove clean
versus explicit edition identity. [Jellyfin music documentation](https://jellyfin.org/docs/general/server/media/music/),
[Navidrome lyric source implementation](https://github.com/navidrome/navidrome/blob/v0.64.2/core/lyrics/sources.go).

## Findings and sources

### Navidrome and shared sidecars

The existing host already configures canonical cover priority, JPEG quality 90,
album art for individual tracks, bounded image/transcoding caches, structured
sidecars ahead of `nd-lyrics`, and a read-only music library. The lyrics plugin
has write access disabled. Preserve those choices. In 0.64.2, external lyric
lookup removes the audio extension, appends the configured suffix, and opens
that path from the library filesystem for the request. A newly created LRC
therefore needs no full audio rescan for `getLyricsBySongId` to see it.
[Navidrome sources](https://github.com/navidrome/navidrome/blob/v0.64.2/core/lyrics/sources.go),
[configuration options](https://www.navidrome.org/docs/usage/configuration-options/).

The prior [lyrics investigation](feishin-lyrics-research.md) explains
why embedded lyrics follow the plugin: imported tags have contained promotional
text. Preserve that policy while creating trusted sidecars. A low-priority plain
sidecar should not inadvertently outrank a later synchronized provider result.
External matching should retain exact title, artist, album and measured duration,
with no punctuation-stripping or fuzzy title matching that erases edition names.
LRCLIB's documented exact endpoint is `/api/get`, with title and artist plus
album and duration for disambiguation. Revalidate returned fields rather than
assuming that any successful HTTP response is safe to persist.
[LRCLIB API](https://lrclib.net/docs).

A maintenance writer should use HTTPS to a fixed origin, a descriptive
User-Agent, serial requests with a delay, response and request limits,
timeouts, negative-cache expiry and retries only on later runs. Stop or back
off on throttling. Reject redirects to arbitrary destinations, malformed JSON,
non-finite durations, oversized data and invalid lyric timings. Treat absence,
instrumental results and provider errors as distinct outcomes. Do not log raw
lyrics, credentials, or account-specific library paths. These are implementation
recommendations, not promises made by the provider.

Create each sidecar atomically without replacement, reject symlink paths, and
ensure path traversal cannot leave the library. A dedicated user and bounded
systemd timer should receive library write access; playback services and the
Navidrome plugin should retain read-only access. Keep state private, sidecars
readable by the media group, and avoid repeatedly probing known misses. A daily
run with a bounded number of requests is adequate; do not rescan all audio or
trigger a full Jellyfin refresh for each track.

### Jellyfin

The inspected integration supports declaring a Music virtual folder but the
current host did not declare one. Add a music collection pointing at the same
canonical library. Jellyfin identifies songs from embedded metadata, supports
disc/total-disc tags, accepts same-stem `.lrc`, `.elrc` and `.txt`, and gives
local images precedence over embedded covers. A Music library is necessary for
those capabilities; installing another lyric downloader alone is insufficient.
[Jellyfin music](https://jellyfin.org/docs/general/server/media/music/).

Jellyfin's `LibraryOptions` has `SaveLyricsWithMedia=false` by default, explicit
lyric provider lists, and `SaveLocalMetadata`. Keep both save flags false when
using the common maintenance writer. Use existing local metadata readers and
realtime monitoring. Avoid broad artist tag delimiters such as `/`, which can
split legitimate artist names; preserve standard multivalue artist tags.
[Jellyfin 10.11 LibraryOptions](https://github.com/jellyfin/jellyfin/blob/v10.11.0/MediaBrowser.Model/Configuration/LibraryOptions.cs).

### Lidarr import and tag safety

The existing Arr reconciler supports media-management and naming singleton
configuration, but not metadata-provider configuration. Lidarr exposes that
separately at `/api/v1/config/metadataprovider`, with `writeAudioTags`,
`scrubAudioTags`, and `embedCoverArt`. Its enum choices are `No`, `NewFiles`,
`AllFiles`, and `Sync`; the API serializer's camel-case spelling should be
confirmed against the running response. [Controller](https://github.com/Lidarr/Lidarr/blob/da7b4dfb1a9e7e1d6625c2dbc3fff96971ab26bd/src/Lidarr.Api.V1/Config/MetadataProviderConfigController.cs),
[resource](https://github.com/Lidarr/Lidarr/blob/da7b4dfb1a9e7e1d6625c2dbc3fff96971ab26bd/src/Lidarr.Api.V1/Config/MetadataProviderConfigResource.cs),
[enum](https://github.com/Lidarr/Lidarr/blob/da7b4dfb1a9e7e1d6625c2dbc3fff96971ab26bd/src/NzbDrone.Core/Configuration/WriteAudioTagsType.cs).

Recommend `newFiles`, `scrubAudioTags=false`, and `embedCoverArt=false`.
`NewFiles` skips existing tracks unless a caller explicitly forces retagging.
Without scrubbing, Lidarr updates its selected MusicBrainz fields in the existing
TagLib object; its writer does not intentionally replace lyric or ReplayGain
fields. Disabling embedding preserves existing pictures while canonical local
covers serve the players. This is source evidence, not a guarantee about every
container's tag serialization. [AudioTagService](https://github.com/Lidarr/Lidarr/blob/da7b4dfb1a9e7e1d6625c2dbc3fff96971ab26bd/src/NzbDrone.Core/MediaFiles/AudioTagService.cs),
[tag writer](https://github.com/Lidarr/Lidarr/blob/da7b4dfb1a9e7e1d6625c2dbc3fff96971ab26bd/src/NzbDrone.Core/MediaFiles/AudioTag.cs).

The host currently enables hardlink imports. Change Lidarr's new imports to
copies when enabling tag writes: modifying a hardlink can also alter the
seeded download. This does not detach existing hardlinks; avoid bulk retagging
existing content. The intended settings change is prospective.

Enable `importExtraFiles` and explicitly allow lyric extensions. The import
implementation matches filenames beginning with the source track stem; this
preserves track-associated sidecars but does not copy a generic album
`cover.jpg` for every import. Native lyric handling recognizes LRC and TXT;
ELRC and other allowed formats fall through to the general extra-file handler.
Both handlers associate imports with tracks and implement moves after renaming.
[ExtraService](https://github.com/Lidarr/Lidarr/blob/da7b4dfb1a9e7e1d6625c2dbc3fff96971ab26bd/src/NzbDrone.Core/Extras/ExtraService.cs),
[lyric extensions](https://github.com/Lidarr/Lidarr/blob/da7b4dfb1a9e7e1d6625c2dbc3fff96971ab26bd/src/NzbDrone.Core/Extras/Lyrics/LyricFileExtensions.cs),
[LyricService](https://github.com/Lidarr/Lidarr/blob/da7b4dfb1a9e7e1d6625c2dbc3fff96971ab26bd/src/NzbDrone.Core/Extras/Lyrics/LyricService.cs),
[OtherExtraService](https://github.com/Lidarr/Lidarr/blob/da7b4dfb1a9e7e1d6625c2dbc3fff96971ab26bd/src/NzbDrone.Core/Extras/Others/OtherExtraService.cs).

### Artwork, Aurral, and AudioMuse

The existing artwork maintenance job already uses shared `cover.jpg`, reviewed
identity matching, bounded image downloads and image decoding, serial requests,
receipts and preservation of unrelated existing art. The host chooses canonical
album artwork consistently across Navidrome and Aurral. Keep this single writer
instead of adding competing Jellyfin/Lidarr cover downloaders. This is a local
source observation from `nix-homelab/scripts/media/artwork.py` and the host's
music modules, not a new upstream feature.

Aurral 2.9.1 already has local patches that write standard native tags and
MusicBrainz identity without remuxing, retain its private IDs in dedicated tags,
and use canonical covers. Preserve those changes. Do not invent Aurral lyric
configuration: no dedicated lyric feature was found in the inspected upstream
source tree. Its discovery and acquisition roles benefit from correct shared
tags and covers, while Navidrome and Jellyfin supply lyric playback.
[Aurral 2.9.1](https://github.com/lklynet/aurral/tree/v2.9.1),
[local native tag patch](../../pkgs/pkgs/by-name/au/aurral/native-audio-tags.patch).

AudioMuse 3.6.0 can consume media-server lyrics for semantic search. Its
`MUSICSERVER_LYRICS_TIMEOUT` default is 2.5 seconds. The installed adapter
retrieved a shared sidecar in about three milliseconds, so this deployment
retains the default. Uncached external plugin requests may still time out.
`LYRICS_ENABLED`, `LYRICS_API_ENABLE`, and `LYRICS_ASR_ENABLE` are enabled by
default. ASR is a search fallback, not authoritative text to publish as shared
lyrics. Keep the existing isolation approval gate and do not silently enable
broader account sharing. [Pinned AudioMuse parameters](https://github.com/NeptuneHub/AudioMuse-AI/blob/31239fa986afb91a15e039e1a9a64ed5a2d6fa12/docs/PARAMETERS.md).

AudioMuse persists application settings in its database; environment variables
are imported for first-start compatibility. Adding an environment variable does
not demonstrate reconciliation of a configured server. Any changed lyric
analysis option must be verified through the running configuration API/database,
without publishing credentials or assuming that Nix evaluation proves runtime
behavior. [Pinned AudioMuse setup documentation](https://github.com/NeptuneHub/AudioMuse-AI/blob/31239fa986afb91a15e039e1a9a64ed5a2d6fa12/README.md).

## Implementation

The reusable `homelab.music.lyrics` module is opt-in. It runs a daily job with
100 serial requests per pass, a one-second delay, a 20-second request timeout,
a one-MiB response limit and a one-hour service timeout. Missing or rejected
matches are cached for seven days. A persistent cursor rotates through the
library so recurring misses cannot starve later tracks. Provider failures stop the pass without
recording a miss. Requests use only LRCLIB's exact endpoint, with redirects
rejected. Provider lookup discloses the requested title, artist, album and duration
to LRCLIB, like other external metadata lookups.

The job selects only the configured Navidrome library. It reads the index in
bounded pages, closes database connections before network requests and never
updates the server database. It validates returned artist, title, album and
duration, requiring a difference of no more than two seconds. It rejects missing,
out-of-order or out-of-range timestamps. Existing lyric files remain untouched,
and missing local files do not block later tracks. Directory descriptors reject
symlink traversal. A complete UTF-8 LRC file is published atomically without
replacing an existing file. Audio files are never opened for writing.

The service runs as the index owner with the shared media group. Its write access
is limited to the music library and private retry state. Memory is capped at
128 MiB, CPU at 25%, and disk I/O receives idle priority. Playback services retain
their read-only library views. See the [module](../../nix-homelab/modules/media/lyrics.nix)
and [helper](../../nix-homelab/scripts/media/lyrics.py).

Lidarr now imports LRC, ELRC, TTML, YAML, SRT and text sidecars and writes standard metadata for
new downloads only. It preserves unowned tags and embedded artwork. Imports use
copies, because tagging a hardlinked library file would also modify its seeding
source. Existing files are not bulk-retagged. This uses additional disk space for
new music downloads while they remain in the download directory.

Jellyfin has a Music library on the same path as Navidrome, with realtime
monitoring enabled and metadata/lyric writes into the library disabled. The
existing canonical artwork job, Aurral tag-writing patches and Navidrome
multi-provider lyric fallback remain in place. No additional metadata daemon,
provider account, credential or listening port was introduced.

A separate AudioMuse oneshot runs after the application is ready. It reconciles
the persisted Navidrome URL through `/api/setup`, probes a changed endpoint
before saving it, and preserves credentials and all unrelated analysis settings.
It uses a projected systemd credential and permits only loopback networking.
An already correct endpoint causes no write or worker restart. Four focused
regression tests cover this behavior and failure handling.

## Validation and limits

All 47 media-helper tests, 63 integration tests and reusable module checks
passed. Ruff, type checking, formatting, Markdown links and scoped secret
scanning also passed. The integration behavior
check initially failed because its existing subtitle test fixture was omitted
from the Nix sandbox; including the declared fixture repaired that check.
Tests cover recording mismatches, invalid timing, existing sidecars, stale index
entries, multiple libraries, symlink rejection, concurrent replacement, bounded
requests and negative-cache expiry.

A scoped live deployment completed through the authorized administrative SSH
route. Both application reconcilers passed dry runs before applying changes.
The first lyric pass requested 69 indexed tracks and wrote 60 synchronized LRC
files with zero execution failures. Nine tracks had no acceptable match and were
left unchanged. The pass took 89 seconds, used less than one second of CPU and
peaked at about 55 MiB of memory. A second pass made zero provider requests and wrote no files.
These are observations for this small library,
not a throughput benchmark.

All 69 indexed tracks had populated title, artist, album and album-artist fields.
None had MusicBrainz recording, release or release-group IDs in the Navidrome
index. Prospective tag writing improves future imports; existing files still
need a reviewed tagging pass to gain those identifiers. No automated bulk
matching or retagging was attempted. Four shared album covers were present.

All 69 audio files retained their inode, size and modification timestamp across
the pass. Unit tests also verify unchanged audio bytes. A sampled track returned
44 synchronized lyric lines through Navidrome's authenticated OpenSubsonic API
and 44 lines through Jellyfin's authenticated lyric API. Jellyfin indexed all 69
tracks and exposed album artwork for the sampled track. This establishes server
interoperability, not every client's rendering or timing accuracy.

The full desktop build and normal NixOS activation subsequently succeeded after
resolving the MPV font conflict. The lyric service and timer now come from the
persistent system configuration; marked temporary units and integration overrides
were removed. The boot profile includes the configuration. This verifies build,
activation and installed boot configuration, without claiming a reboot test.

The library grew to 119 tracks during verification. All 50 new imports have
MusicBrainz recording and release IDs, confirming the prospective tagging policy.
The new lyric pass wrote another 49 sidecars with zero failures. Total synchronized
sidecar coverage is 109 tracks. The next pass requested and wrote nothing, took
about 0.4 seconds and peaked at about 19 MiB. Both servers index all 119 tracks;
the same sampled track returns identical text and 44 synchronized lines through
both authenticated APIs. Live Lidarr settings confirm copied imports, sidecar
preservation, new-file tagging and retained unowned metadata.

Review of the older files found title, timing and release-edition ambiguities.
Their tags remain intact, including existing hardlinks. Assigning recording or
release IDs solely from the managed application's selected release could encode
the wrong edition. No bulk retagging was performed.

The persisted AudioMuse server address was unreachable even though its environment
variable was correct. The new reconciler repaired the saved address and completed
successfully. This fixes the server integration without changing the isolation
approval gate or enabling shared account access.

The installed lyric embedding loader also had a Docker-only model path despite
the native package containing the model. The service now supplies explicit GTE
model, GTE tokenizer and Silero paths from its pinned model package. A single-track
analysis using server lyrics and cached models produced a finite 768-dimensional
embedding and a finite 27-dimensional topic vector in about 1.2 seconds using
the activated worker environment. All five application child processes have valid
store paths for the lyric models. The
check forced read-only database connections and disabled provider and transcription
fallbacks in memory. It consumed no audio and downloaded no models. This exercises
lyric analysis, without claiming a completed library-wide semantic index.

Every indexed track now has a canonical album cover in its directory. One
untagged album required a reviewed release-group lookup because omitted punctuation
in its tag defeated the provider search. Artist, normalized title and year matched
the authoritative release group before the standard artwork helper downloaded
and recorded its approved front cover. The audio files were unchanged.

Exact title, album and duration matching cannot prove a lyric's clean/explicit
edition or textual accuracy. The ten misses retain Navidrome's on-demand plugin
fallback; they do not receive invented lyrics. Existing richer sidecars remain
preferred, but a new shared LRC takes precedence over the plugin even if a
provider might offer word timing. Client support determines the available
presentation. Client UI rendering remains unverified in this session. AudioMuse's household-isolation gate remains unchanged.
