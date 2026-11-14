# Research question

Reviewed: 2026-09-23. Scope: extension options for the media stack, especially
Jellyfin 12.1, Seerr 3.4.1, Sonarr, Radarr, Prowlarr, Bazarr, and qBittorrent.
The decision is which additions improve playback or library use without adding
unnecessary code, network access, or maintenance.

## Answer

Jellyfin has a [documented plugin catalog](https://jellyfin.org/docs/general/server/plugins/).
The strongest candidates for this installation are Subtitle Extract for
embedded subtitles and Intro Skipper for episodic viewing. AniList is an
optional metadata source when anime matching is actually poor. TMDb Box Sets
is useful only if automatic movie collections are wanted. Test each on a
small library before enabling a full scan. None is needed to make Seerr request
future-only episodes; that workflow belongs to Sonarr monitoring.

## Findings and sources

| Extension | Potential benefit | Cost or constraint |
| --- | --- | --- |
| [Subtitle Extract](https://jellyfin.org/docs/general/server/plugins/#subtitle-extract) | Extracts embedded subtitles before playback, avoiding some delays when a client cannot direct play a subtitle stream. | Initial extraction consumes CPU and storage. It complements the configured Bazarr service rather than replacing its subtitle searches. The [official stable catalog](https://repo.jellyfin.org/files/plugin/manifest.json) listed version 8 with target ABI 12.0.0.0 on the review date. |
| [Intro Skipper](https://github.com/intro-skipper/intro-skipper) | Detects TV intro and credit segments for Jellyfin clients that use media segments. | Third-party repository, audio analysis cost, and a Jellyfin FFmpeg build with Chromaprint; the maintainer lists Jellyfin 12.0 or newer as a requirement. Client support and scan cost should be checked with one series first. |
| [AniList](https://jellyfin.org/docs/general/server/plugins/#anilist) | Additional anime metadata source. | Sends metadata queries to AniList and can change matching results. The [official stable catalog](https://repo.jellyfin.org/files/plugin/manifest.json) listed version 15 with target ABI 12.1.0.0. Use only for a demonstrated metadata gap, and test names and episode ordering first. |
| [TMDb Box Sets](https://jellyfin.org/docs/general/server/plugins/#tmdb-box-sets) | Creates and updates movie collections from TMDb's collection data. | Adds a scheduled library task and depends on TMDb identifiers. The [official stable catalog](https://repo.jellyfin.org/files/plugin/manifest.json) listed version 15 with target ABI 12.1.0.0. |
| [Playback Reporting](https://jellyfin.org/docs/general/server/plugins/#playback-reporting) | Records local watch statistics with retention controls. | Stores per-user viewing history. The [official stable catalog](https://repo.jellyfin.org/files/plugin/manifest.json) listed version 19 with target ABI 12.0.0.0, but [open compatibility and export reports](https://github.com/jellyfin/jellyfin-plugin-playbackreporting/issues) make it lower priority for this newly updated server. |

The official [Seerr extension documentation](https://docs.seerr.dev/category/extending-seerr/)
and [notification integrations](https://docs.seerr.dev/using-seerr/notifications/)
cover API/configuration tools and webhooks rather than a user-installed feature
plugin catalog. Sonarr's [Connect triggers](https://github.com/Servarr/Wiki/blob/master/sonarr/settings.md#connect)
and import lists are integration points, but a list can add and search many
unwanted shows if configured broadly. qBittorrent supports Python search
plugins, and its [own installation guide](https://github.com/qbittorrent/search-plugins/wiki/Install-search-plugins)
warns that third-party scripts require review. The existing Prowlarr-to-Arr
path already centralizes indexers, so qBittorrent search scripts would duplicate
that function for this installation.

## Validation and limits

Read-only review of upstream documentation and the official Jellyfin stable
manifest on 2026-09-23. The running server reported Jellyfin 12.1 and Seerr
3.4.1. No plugin was installed or benchmarked; catalog target ABI is a
compatibility declaration, not proof of correct behavior on this host.

## Implication for this repository

Keep third-party Jellyfin code out of the base media profile. If a plugin is
chosen, pin its compatible version in a separate module, restrict any new
outbound integration to the service that needs it, and verify one library and
one client before scheduling a whole-library task. Bazarr already handles
subtitle acquisition, and the current Seerr/Sonarr integration is managed
declaratively, so adding duplicate automation should require a clear use case.
