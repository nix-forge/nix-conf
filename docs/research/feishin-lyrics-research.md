# Feishin lyrics through Navidrome

Reviewed: 2026-09-24. Scope: Feishin 1.17.0, Navidrome 0.64.x, and the
`nd-lyrics` 8.1.0 plugin. This note addresses synchronized lyric coverage and
selection for a shared music library.

## Finding

Feishin can display lyrics returned by Navidrome's OpenSubsonic
`getLyricsBySongId` endpoint. Its **Prefer local lyrics** setting selects that
server response ahead of Feishin's separate internet fetchers. Navidrome can
resolve structured sidecars, embedded tags, and the `nd-lyrics` plugin in the
configured order. The current desktop configuration enables this path for every
Navidrome user and library. [Feishin 1.17.0 request and feature detection](https://github.com/jeffvli/feishin/blob/v1.17.0/src/renderer/api/subsonic/subsonic-controller.ts#L2047-L2085),
[Feishin's selection logic](https://github.com/jeffvli/feishin/blob/v1.17.0/src/renderer/features/lyrics/api/lyrics-api.ts#L84-L145),
[OpenSubsonic endpoint](https://opensubsonic.netlify.app/docs/endpoints/getlyricsbysongid/).

Feishin's developer specifically recommends **Prefer local lyrics** for the
Navidrome Lyrics Plugin. The setting defaults to true in Feishin 1.17.0's
renderer state, but an existing user's saved setting can differ. The desktop
client's `config.json` list of NetEase and LRCLIB is its separate internet
fetcher list; it does not show the effective value of that renderer preference.
[Feishin 1.14.0 release notes](https://github.com/jeffvli/feishin/releases/tag/v1.14.0),
[Feishin 1.17.0 defaults](https://github.com/jeffvli/feishin/blob/v1.17.0/src/renderer/store/settings.store.ts#L2046-L2063).

The reported failure strongly points to contaminated file metadata: Feishin
displayed a promotional URL in place of lyrics for an imported track, and
Navidrome's logs have also shown promotional URL text in imported artist tags.
The earlier priority put `embedded` before `nd-lyrics`, allowing a bad embedded
lyric to block the plugin. The desktop now puts curated structured sidecars
first, `nd-lyrics` second, and embedded lyrics after it. A plugin miss can still
fall back to embedded content. This prioritizes better matches for imported files, though a
wrong external match can now hide a good embedded lyric; curate a sidecar for
that case.
[Navidrome options](https://www.navidrome.org/docs/usage/configuration/options/),
[desktop declaration](../../hosts/nixos/desktop/local/homelab/music/discovery.nix).

## Provider quality and caching

`nd-lyrics` supports line and word timing and can query several providers. Its
best-sync-level mode ranks word timing above line timing above plain text. This
ranking measures synchronization, not whether the text matches a particular
recording. Album matching can reject wrong candidates, but can also lose valid
matches when album tags differ; its LRCLIB provider skips fallback lookups
without the album when that option is enabled. [Plugin README](https://github.com/J0R6IT0/navidrome-lyrics-plugin/blob/v8.1.0/README.md),
[provider modes](https://github.com/J0R6IT0/navidrome-lyrics-plugin/blob/v8.1.0/src/config/providers.rs),
[LRCLIB provider](https://github.com/J0R6IT0/navidrome-lyrics-plugin/blob/v8.1.0/src/providers/services/lrclib.rs).

The desktop also enables `preferUncensored`, but in the plugin's sync mode this
only breaks ties between candidates at the same sync level. A censored word
synced result still wins over an uncensored line synced result. The plugin
detects masked words containing asterisks; it cannot recover their original
text or distinguish an intentionally clean recording from an explicit one.
The listener has reported censored Jack Harlow lyrics, but the specific track,
lyric source, and recording edition are not established. Changing the global
sync preference would reduce timing quality for other users without proving a
better match. For a confirmed explicit recording, a reviewed uncensored
sidecar is the reliable correction. [Ranking tests](https://github.com/J0R6IT0/navidrome-lyrics-plugin/blob/v8.1.0/src/fetch/ranking.rs),
[censor detection](https://github.com/J0R6IT0/navidrome-lyrics-plugin/blob/v8.1.0/src/format/censor.rs).

LRCLIB's exact lookup uses track and artist, with album and duration helping
disambiguate recordings. Its API documents a two-second duration match, `404`
for no match, and `429` throttling. On 2026-09-24, a small public search for
several reported titles found synchronized candidates for two and received one
HTTP 503. This establishes upstream candidate coverage and a transient service
failure; it does not establish what the desktop's plugin returned for those
files. [LRCLIB API documentation](https://lrclib.net/docs).

In `nd-lyrics` 8.1.0, the default negative cache lasts 24 hours, while its
per-format defaults keep plain results for 72 hours and LRC or Lyricsfile for
168 hours, with TTML and ELRC kept for 336 hours. The desktop now uses a
two-hour negative cache and enables those per-format lifetimes. This makes a
failed lookup recover sooner and lets plain results be reconsidered sooner than
high-quality synchronized results. It increases requests for persistent misses,
but lookups remain on demand and cached by the plugin. [Cache defaults](https://github.com/J0R6IT0/navidrome-lyrics-plugin/blob/v8.1.0/src/config/ttl.rs),
[plugin behavior](https://github.com/J0R6IT0/navidrome-lyrics-plugin/blob/v8.1.0/README.md).
The new lifetimes apply to entries written after the change; existing plugin
cache entries keep their original expiry. [Cache writes](https://github.com/J0R6IT0/navidrome-lyrics-plugin/blob/v8.1.0/src/cache.rs).

## Nix Home Lab integration

Use one Navidrome server to resolve lyrics for all OpenSubsonic clients. A
deployment selecting the plugin needs `services.navidrome.plugins`, the matching
name in `services.navidrome.settings.LyricsPriority`, and plugin configuration
and permissions in Navidrome. The desktop bootstrap grants the plugin all users
and libraries without file write access; `writeLyrics = false` avoids writing
provider results into a read-only shared library. New users therefore receive
the same server lyric source without separate provider accounts.
[Plugin setup](https://github.com/J0R6IT0/navidrome-lyrics-plugin/blob/v8.1.0/README.md),
[desktop integration](../../hosts/nixos/desktop/local/homelab/music/discovery.nix),
[Nix Home Lab media policy](../../nix-homelab/modules/media/default.nix).

For a poor result, check Feishin's selected lyric source and **Prefer local
lyrics**, then inspect `getLyricsBySongId` for that song ID. Compare whether the
response is absent, plain, line synced, or word synced before changing global
priority. A curated sidecar alongside the audio file is the deterministic fix
for an important track when external providers disagree. Navidrome supports
TTML, YAML, ELRC, LRC, and SRT structured sidecars. [Navidrome 0.63.0 release](https://github.com/navidrome/navidrome/releases/tag/v0.63.0),
[Feishin selection logic](https://github.com/jeffvli/feishin/blob/v1.17.0/src/renderer/features/lyrics/api/lyrics-api.ts#L84-L145).

For a repeatable library cleanup, [LRCGET](https://github.com/tranxuanthang/lrcget/blob/main/README.md)
can create same-name LRC sidecars, while the [beets lyrics plugin](https://beets.readthedocs.io/en/stable/plugins/lyrics.html)
can fetch synchronized lyrics during a controlled import and record the provider.
Both paths write to the music library and require a reviewed backup, accurate
artist and album tags, and rate-limited provider use. They are suitable for a
curated subset first; neither can reliably identify a recording from a bad tag
or guarantee word-level timing. Shared sidecars improve every Navidrome client,
not only Feishin.

## Validation and limits

On the desktop, Navidrome 0.64.0 was running, its log showed `nd-lyrics`
discovered and enabled, and the generated configuration included
`nd-lyrics` in `LyricsPriority`. The listener reported that **Prefer local
lyrics** is enabled and that a promotional URL appeared in place of lyrics.
The current account could not read the protected library or authenticate as
the listener, so the exact song response and embedded tag were not inspected.
The desktop system build passed, and its generated Navidrome and plugin JSON
contain the new priority and cache values. After activation, the running
Navidrome service used the new configuration, its bootstrap completed, and
`nd-lyrics` loaded with the Lyrics capability. A subsequent request reached
the plugin. One provider rejected a candidate four seconds away from the
track's 205-second duration under the configured three-second tolerance;
another request was canceled during a rapid track change. The listener then
confirmed that at least one previously affected track displayed lyrics in
Feishin. This verifies a client-visible improvement, but does not measure
coverage, text accuracy, or timing across the library. The build included
other pending desktop changes, so its success does not isolate this adjustment
from the rest of the working tree.
The Navidrome web player is not a valid
test for plugin lyrics according to the plugin's own documentation.
[Plugin README](https://github.com/J0R6IT0/navidrome-lyrics-plugin/blob/v8.1.0/README.md).
