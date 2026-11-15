# Keeping album transitions out of song shuffle

Reviewed: 2026-10-09. Scope: Navidrome 0.64.2, Feishin 1.17.0,
and OpenSubsonic's random-song API. Repository baseline
`84e37f5d83e1b218ce8c2c843fe3f9ead479b12c`.

## Answer

Keep every track in the music library and album order. Apply a separate playback
policy when selecting standalone songs. Explicit per-track decisions are the
most reliable input. Titles and duration can identify candidates, but a short
track can be a complete song and a track named "Interlude" can be intended for
standalone listening. This is a design recommendation, not an upstream metadata
guarantee.

Use a standalone-song smart playlist with two ordinary override playlists.
"Album-only tracks" excludes reviewed tracks and "Shuffle inclusions" keeps
reviewed exceptions to title rules. Explicit exclusion wins if a track belongs
to both. This works through the existing client playlist editor and requires
no audio-file changes. A custom tag remains an option for portable decisions.
The smart playlist does not automatically change the existing Shuffle All
button. Play the filtered playlist explicitly. Avoid removing tracks from the
index or changing their ratings to encode this policy.

## Findings and sources

### Existing metadata cannot decide every case

MusicBrainz's documented recording properties contain identity, names, duration,
and descriptive information. They do not define a recording type for "skit",
"interlude", or "album only". Its `Spokenword` release-group type describes
an entire non-music release. Applying it to one skit in a music album would
misrepresent the release. A MusicBrainz recording identifier can identify a
reviewed decision, but does not supply the decision itself.
[Recording model](https://musicbrainz.org/doc/Recording),
[release-group types](https://musicbrainz.org/doc/Release_Group/Type).

### Custom tags and smart playlists are supported

Navidrome imports custom tags only when `Tags` declares them. Each definition
requires `Aliases`; names are case-insensitive. `Album = false` keeps the
field at track scope. A full scan is required after changing the tag
configuration. For example, an opt-out field can use:

```toml
Tags.ShuffleExclude.Aliases = ["shuffleexclude", "txxx:shuffleexclude"]
Tags.ShuffleExclude.Album = false
```

This is an example policy name, not a standard tag.
[Custom tag configuration](https://www.navidrome.org/docs/usage/configuration/custom-tags/).

The smart-playlist format accepts custom fields and random sorting. An
illustrative definition is:

```json
{
  "name": "Standalone songs",
  "public": false,
  "all": [{ "isNot": { "shuffleexclude": "1" } }],
  "sort": "random"
}
```

In 0.64.2, `isNot` for a tag uses a negated existence query. Tracks with no tag
remain eligible, and a multivalue tag containing `1` is excluded even if it has
other values. File-based playlists require import scanning; this example does
not imply that merely writing a JSON file outside the library imports it.
[Smart playlists](https://www.navidrome.org/docs/usage/features/smart-playlists/),
[0.64.2 criteria implementation](https://github.com/navidrome/navidrome/blob/v0.64.2/persistence/criteria_sql.go),
[playlist scan phase](https://github.com/navidrome/navidrome/blob/v0.64.2/scanner/phase_4_playlists.go).

### Shuffle All bypasses smart playlists

OpenSubsonic `getRandomSongs` accepts size, genre, year bounds, and music-folder
selection. It has no standard skip-shuffle tag or playlist argument. Navidrome
0.64.2's handler applies those filters directly before requesting random media
files. Creating a smart playlist cannot affect this query.
[OpenSubsonic endpoint](https://opensubsonic.netlify.app/docs/endpoints/getrandomsongs/),
[Navidrome handler](https://github.com/navidrome/navidrome/blob/v0.64.2/server/subsonic/album_lists.go#L216-L240).

Feishin 1.17.0's Shuffle All song mode calls `getRandomSongList`, then queues
the returned songs. Album mode separately queues selected albums. This is a
suitable boundary for applying song-only policy without breaking sequential
album playback. A managed client change covers that client; other clients need
to use the filtered playlist or implement the same policy.
[Feishin Shuffle All](https://github.com/jeffvli/feishin/blob/v1.17.0/src/renderer/features/player/components/shuffle-all-modal.tsx).

### Native API supports editable overrides

The authenticated native API accepts `POST /api/playlist` with exact
`Content-Type: application/json`. Fields include `name`, `comment`, `ownerId`,
`public`, `sync`, and `rules`. Use `rules: null` for ordinary override playlists.
For the smart playlist, nest the criteria object under `rules`. Updates use
`PUT /api/playlist/{id}` with the changed fields. Preserve override memberships
by leaving the track endpoints untouched when reconciling metadata.
[API router](https://github.com/navidrome/navidrome/blob/v0.64.2/server/nativeapi/native_api.go),
[playlist model](https://github.com/navidrome/navidrome/blob/v0.64.2/model/playlist.go),
[Feishin request schema](https://github.com/jeffvli/feishin/blob/v1.17.0/src/shared/api/navidrome/navidrome-types.ts).

`inPlaylist` and `notInPlaylist` accept playlist IDs. Use each listener's own
override IDs and owner rather than depending on another user's private
playlist. Criteria enforce playlist visibility.
[Playlist criteria implementation](https://github.com/navidrome/navidrome/blob/v0.64.2/persistence/criteria_sql.go).

Title `is` and `isNot` use SQL equality without normalizing the value.
`contains` and `notContains` use `LIKE`, which SQLite normally treats as
case-insensitive for ASCII. Do not assume Unicode case folding or use a broad
`intro` substring. Title patterns remain fallible and need include overrides.
[Criteria implementation](https://github.com/navidrome/navidrome/blob/v0.64.2/persistence/criteria_sql.go),
[SQLite expressions](https://sqlite.org/lang_expr.html).

## Validation and limits

Inspected the primary documentation and versioned source linked above. Reviewed
this note for publication safety and portable examples. The implemented helper
created three private playlists through the native API. Its next run planned
zero writes. The running server selected 114 of 120 tracks, excluding six explicit
skit/interlude title matches and retaining one short track. An independent title
predicate produced the same membership set.

Temporary private verification playlists exercised the real server's criteria.
Including a title-excluded track restored it; explicit exclusion won when a
track was in both override playlists. The excluded track remained in its album.
Verification playlists were removed, and the listener's override memberships
were untouched. These checks exercise selection and album membership, not audio
playback or every client's shuffle behavior.

Ten focused Python tests passed. Ruff lint/formatting, type checking, Nix parsing,
and evaluation of the Python writer derivation passed. Documentation relative
links and the scoped publication/secret scan passed. A fresh read-only review
found no blocking issues for the supported playlist scope.
The first local pytest invocation failed because the timeout plugin loaded twice;
the repository's explicit plugin-loading policy resolved that environment issue.
The maintenance service's full Nix evaluation/build was deferred because the
desktop workload queue is occupied by unrelated builds. The queued checks were
cancelled; they did not produce validation results. No full system activation was performed.
Exact file-tag encoding and scanner behavior need fixture tests before introducing
an automated tag writer.

## Implication for this repository

Preserve the existing shared-library and read-only playback-server boundaries
described in [the metadata investigation](music-metadata-research.md). Reconcile
the listener-owned override playlists and smart-playlist rules through the
native API. Preserve user-managed memberships. Apply only conservative title
markers, with inclusion overrides for false positives. Avoid exclusions based
only on duration or broad substring matches such as `intro`. The filtered
playlist is the supported playback entry point; a client patch would be a
separate decision if the existing Shuffle All button must use this policy.

## Using the implemented policy

In Feishin or Navidrome, open **Standalone songs** and shuffle that playlist.
Add a track to **Album-only tracks** to exclude it. Add a track to **Shuffle
inclusions** to keep it despite an automatic title hint. Exclusion takes
precedence if both playlists contain the track. Remove a track from an override
playlist to undo that decision. These controls belong to the configured listener
and are private; another account needs its own policy.

Automatic hints exclude exact `skit` and `interlude` titles in lowercase,
title case, and uppercase, plus `(skit)`, `[skit]`, `(interlude)`, and `[interlude]`
markers anywhere in the title. Bracket markers are ASCII case-insensitive.
Intro/outro titles, arbitrary short tracks, and unlabelled speech remain eligible.
Review those explicitly; no algorithm can infer every album-only piece from
these tags. Legitimate songs with a matched label can use Shuffle inclusions.

The reusable [shuffle module](../../nix-homelab/modules/media/shuffle.nix)
packages the [API helper](../../nix-homelab/scripts/media/configure_music_shuffle.py).
It maintains managed smart criteria on boot and daily without replacing the
override memberships or modifying unrelated playlists. Stable server ordering
keeps paginated results consistent; the playback client performs the shuffle.
The consuming host selects credentials, required mounts and account readiness
through the [feature options](../../nix-homelab/docs/portable-features.md).

## Adding new albums

Standalone songs stores selection rules, not a snapshot of track IDs. There is
no album allowlist or track-count limit. The only IDs in its criteria refer to
the two editable override playlists, discovered from the server during setup.
Every newly indexed album is subject to the same rules automatically.

Navidrome refreshes smart membership when clients access the playlist, subject
to its refresh delay. Reopen or refresh the playlist after the library scan,
then start a new shuffle. An already-created playback queue or offline copy
is a snapshot and will not gain new tracks automatically.
[Smart playlist refresh](https://www.navidrome.org/docs/usage/features/smart-playlists/#refreshing-playlists).

The maintenance timer repairs playlist definitions; it is not required to add
new albums to the existing smart playlist. Unlabelled album-only pieces still
need a reviewed exclusion. New title hints apply without editing the rules.
A read-only verification of the stored native API resource confirmed smart
criteria, no album/track allowlist, and no fixed or percentage limit. This
verification did not import a synthetic album into the listener's library.

The native Shuffle All button, existing queues, other playlists, song radio,
and Jellyfin's independent shuffle remain unrestricted. This policy takes effect
when playback starts from Standalone songs.
