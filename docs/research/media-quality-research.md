# Movie and television quality policy

Reviewed: 2026-10-03. Scope: Radarr, Sonarr v4, Recyclarr, and TRaSH Guides revision `a9486f6465d4483993dec638131272b397a4338e`. The policy targets mixed playback devices.

## Answer

Use a combined 2160p/1080p profile with upgrades enabled for ordinary movies and television. Prefer HDR and compatible dynamic HDR releases, retain 1080p fallback, and reject known release-group upscales. Admit disc/remux sources when prioritizing source quality and lossless audio. Keep anime source selection separate. A release name can support filtering, but cannot establish native production resolution or actual playback compatibility.

## Findings and sources

### Resolution and upgrade policy

The pinned guide's [combined television profile](https://github.com/TRaSH-Guides/Guides/blob/a9486f6465d4483993dec638131272b397a4338e/docs/json/sonarr/quality-profiles/web-2160p-combined.json) admits WEB 2160p above WEB 1080p, enables upgrades, sets the quality cutoff to WEB 2160p, permits minimum format score zero, and uses custom-format cutoff 10000. This supports acquiring a fallback and upgrading it later.

Quality ranking precedes custom-format score. Group only genuinely interchangeable sources at the same rank. Set native proper/repack behavior to `Do Not Prefer` when the explicit proper/repack custom formats own that preference. The [Sonarr profile guide](https://trash-guides.info/Sonarr/sonarr-setup-quality-profiles/) explains this ordering and recommends a high format cutoff so better matching releases remain upgrade candidates.

Changing a profile does not itself search all old indexer listings. Radarr's normal RSS processing observes newly posted releases; a targeted search is needed to examine existing releases immediately. Verify the assigned profile and monitoring state before searching. Sources: [Servarr FAQ source](https://github.com/Servarr/Wiki/blob/master/radarr/faq.md) and [Radarr settings](https://wiki.servarr.com/radarr/settings).

### HDR and audio preferences

The [Radarr guide](https://trash-guides.info/Radarr/radarr-setup-quality-profiles/) recommends the catch-all HDR format for HDR displays. DV Boost and HDR10+ Boost express optional preferences. Dolby Vision without an HDR10 fallback needs compatible playback devices; retaining the negative fallback filter is sensible while those devices are unverified. A 4K display alone does not establish Dolby Vision, HDR10+, or audio support.

Prefer HDR rather than requiring it for every 2160p WEB release. Some legitimate 4K WEB sources are SDR. The [Sonarr format-group guidance](https://trash-guides.info/Guide-Sync/sonarr-cf-groups/) explicitly allows SDR WEB in its `SDR (no WEBDL)` policy because such releases may improve on 1080p. Requiring every title to have HDR or Atmos can leave otherwise suitable media unavailable.

Dolby Atmos is audio. Dolby Vision and HDR10+ are video formats. Dolby documents Atmos delivery through both Dolby Digital Plus and Dolby TrueHD in its [home theater technical paper](https://professional.dolby.com/siteassets/tv/home/dolby-atmos/dolby-atmos-for-home-theater.pdf). The two audio carriers have different compression and playback requirements. A title labeled Atmos is not automatically lossless.

A WEB-only quality profile excludes disc remuxes by construction. The guide's [Remux + WEB 2160p profile](https://github.com/TRaSH-Guides/Guides/blob/a9486f6465d4483993dec638131272b397a4338e/docs/json/radarr/quality-profiles/remux-web-2160p.json) permits remux upgrades; its [UHD Bluray + WEB profile](https://github.com/TRaSH-Guides/Guides/blob/a9486f6465d4483993dec638131272b397a4338e/docs/json/radarr/quality-profiles/uhd-bluray-web.json) chooses encoded Blu-ray instead. These are separate storage and playback choices.

The pinned [TrueHD Atmos score](https://github.com/TRaSH-Guides/Guides/blob/a9486f6465d4483993dec638131272b397a4338e/docs/json/radarr/cf/truehd-atmos.json) defaults to 5000 and [DD+ Atmos](https://github.com/TRaSH-Guides/Guides/blob/a9486f6465d4483993dec638131272b397a4338e/docs/json/radarr/cf/ddplus-atmos.json) to 3000. These outweigh the 500-point HDR preference. Therefore copying those audio scores into a custom WEB profile changes its priorities. For a video-first policy, make audio a smaller tie-breaker and test combinations explicitly. This is an implementation recommendation, not the guide's default scoring.

### Upscales and generated HDR

The pinned [Radarr Upscaled definition](https://github.com/TRaSH-Guides/Guides/blob/a9486f6465d4483993dec638131272b397a4338e/docs/json/radarr/cf/upscaled.json) and [Sonarr Upscaled definition](https://github.com/TRaSH-Guides/Guides/blob/a9486f6465d4483993dec638131272b397a4338e/docs/json/sonarr/cf/upscaled.json) inspect release-title patterns, including known upscale labels and groups. Both default to -10000. Add the Sonarr definition as well as Radarr's existing one.

The [Generated Dynamic HDR definition](https://github.com/TRaSH-Guides/Guides/blob/a9486f6465d4483993dec638131272b397a4338e/docs/json/radarr/cf/generated-dynamic-hdr.json) rejects identified groups in combination with dynamic HDR labels. It does not prove that every unflagged release contains studio-authored metadata.

Inference from these definitions: neither filter examines production masters or original photography. They cannot exclude all unlabelled upscales, and they cannot reliably distinguish a studio 4K master derived from a 2K digital intermediate. A native-4K-only collection needs title-specific production or mastering evidence. Do not describe these filters as a native-resolution guarantee.

### Anime and file sizes

The [anime guide](https://trash-guides.info/Sonarr/sonarr-setup-quality-profiles-anime/) uses a distinct profile with source grouping and release-group preferences. It groups Blu-ray encodes and remuxes together and merges HDTV with WEB at corresponding resolutions to account for anime naming. Dual audio is an optional preference. Preserve useful 1080p anime releases instead of treating resolution as proof of quality.

Quality definitions apply to an entire application instance, shared by its profiles. They are sizes per minute, not absolute file limits. Recyclarr supports the guide values plus per-quality overrides. Source: [Recyclarr quality definitions](https://recyclarr.dev/reference/configuration/quality-definition/).

The pinned [movie definitions](https://github.com/TRaSH-Guides/Guides/blob/a9486f6465d4483993dec638131272b397a4338e/docs/json/radarr/quality-size/movie.json) use minimum WEB rates of 12.5 MB/min for 1080p and 34.5 for 2160p. The pinned [series definitions](https://github.com/TRaSH-Guides/Guides/blob/a9486f6465d4483993dec638131272b397a4338e/docs/json/sonarr/quality-size/series.json) use 15 and 25 respectively. The guide caps are effectively unlimited in these applications. Smaller local caps are resource policy, not a measure of native resolution. The [anime definitions](https://github.com/TRaSH-Guides/Guides/blob/a9486f6465d4483993dec638131272b397a4338e/docs/json/sonarr/quality-size/anime.json) use a 5 MB/min floor; a shared instance cannot apply separate size definitions per anime profile.

### Declarative ownership and observed configuration

The inspected [quality module](../../nix-homelab/modules/optional/quality/default.nix) initially admitted only WEB sources in both profiles. Its 2160p profile used minimum format score 1 and awarded HDR 500 points. Its comment claimed 2160p required HDR, but a +5 proper/repack score alone meets that minimum. Sonarr dual audio can also meet it. This is a configuration-level finding, not a reconstruction of any particular download.

The inspected [format list](../../nix-homelab/modules/optional/quality/formats.nix) blocked upscales only in Radarr and did not express DV, HDR10+, or Atmos preferences. Unknown existing format scores remained unmanaged. According to [Recyclarr's profile reference](https://recyclarr.dev/reference/configuration/quality-profiles/), `reset_unmatched_scores.enabled = true` clears undeclared scores, with exceptions available. Use that only for profiles the module owns, after inspecting existing scores. Leave other profiles and format definitions intact.

## Repository policy and validation

The implementation ranks remux, Blu-ray encode, and WEB sources in that order
within each resolution. All admitted 2160p sources outrank 1080p. HDR scores 1500,
DV adds 600, HDR10+ adds 100, and audio ranges up to 500 for TrueHD Atmos. This
custom policy keeps HDR ahead of audio within a quality tier. It deliberately
allows higher-ranked SDR sources to outrank lower-ranked HDR sources.

Both profiles admit SDR with minimum score zero and allow upgrades with format
cutoff 10000. Both reject labeled upscales and known generated-HDR groups. Sonarr
uses the pinned guide's Radarr generated-HDR rules through a separate custom
format provider. Dolby Vision without HDR fallback remains excluded for mixed
clients. The profile does not require Atmos, so stereo-only titles remain usable.

The 4K example now uses the same module policy as the consuming host. The host
selects the combined profile for new movie and TV requests. Anime requests use
`Homelab Anime`, based on the pinned guide's anime profile with its grouped
sources, release-group ranking, 1080p ceiling and lower-resolution fallbacks.
Minimum score zero deliberately permits unranked groups. Existing anime using
the former managed 1080p default can migrate without changing custom profiles.
Seerr resolves this profile by name instead of hard-coding a database ID, and
validates both library roots. Its [API schema](https://github.com/seerr-team/seerr/blob/v3.4.1/seerr-api.yml)
defines separate anime profile and directory settings. Pinned series size
definitions remain instance-wide.

On x86_64 Linux, `configuration-optional` and the `quality` NixOS VM check passed.
The VM exercises real Radarr/Sonarr release parsing, HDR/audio preferences,
upscale and generated-HDR rejection, Dolby Vision compatibility, anime source
and group policy, preview non-mutation, and repeated-sync preservation of
unmanaged scores. CF array order is normalized for the preservation comparison;
quality precedence remains ordered. The test waits for the exact guide size
floors before recording its baseline because Arr caches those values for five
seconds. Unlimited sizes may omit the API's maximum field, which the test accepts. A stale assertion claiming a Japanese-only
subtitle label matched the English/multilingual filter was corrected.

The Seerr request tests passed, covering named anime profile resolution,
missing/ambiguous profiles, invalid roots, dry runs, and repeated reconciliation.
The full desktop configuration built and activated successfully through the
repository's desktop workload runner. Recyclarr and Seerr reconciliation both
completed successfully. Live checks confirmed the movie/TV default, named anime
routing, and migration of the existing managed anime assignment. Synthetic
release parsing on both live managers confirmed SDR eligibility, HDR/DV
preference, and rejection of labeled upscales, generated HDR, and DV without
fallback. A live read-only release
search changed from rejecting every available 2160p candidate to admitting
2160p SDR WEB and HDR/DV Blu-ray candidates. This verifies current eligibility,
not native mastering or historical availability. A targeted movie upgrade search
successfully handed a release labeled as a 2160p HDR/DV remux to the download
client. It is downloading without reported errors; completion and media-stream
verification remain pending. Formatting, Markdown checks,
and a redacted secret scan of the task patch and research note passed.

No filename-based policy guarantees native 4K, and no server setting establishes
that every screen or audio path supports HDR or Atmos passthrough. This research
does not establish historical indexer availability. Profiles permit future
upgrades; existing-indexer searches remain separate operations.

## Audio playback preference

A multi-language file can mark a dubbed track as default while retaining a
higher-quality English track. Managed playback settings use
`AudioLanguagePreference = "eng"` and `PlayDefaultAudioTrack = false` so the
language preference takes precedence over the file's default-track flag.
Other user configuration fields are preserved. Jellyfin's
[stream-selection implementation](https://github.com/jellyfin/jellyfin/blob/master/Emby.Server.Implementations/Library/MediaStreamSelector.cs)
checks the default flag first only when that preference is enabled; otherwise
it selects from the language-ranked streams. This selects a language, not a
universal audio-codec ranking. Actual Atmos output still depends on the player
and audio path. The stored audio bitstreams remain unchanged.

`RememberAudioSelections = false` also prevents a remembered numeric audio index
from choosing a different language after a file upgrade reorders tracks.
This favors the English preference on each playback; manually selected audio
tracks are not remembered between plays. The
[media-source manager](https://github.com/jellyfin/jellyfin/blob/master/Emby.Server.Implementations/Library/MediaSourceManager.cs)
otherwise applies the stored audio index before language-based selection.

Validation covered seven playback-adapter tests, including dry-run behavior,
configuration preservation, and idempotence. After activation, live playback-info
responses selected the English TrueHD Atmos track for both managed accounts,
including an account with a stale remembered index from an earlier file.
This verifies server-side selection, not physical Atmos output on every device.
