# Research question

Reviewed: 2026-09-23. Scope: Seerr 3.4.1 (`69f73a6`, released
2026-07-30), Sonarr 4.0.20.3014 (`cab419a`), and the repository's declared
Seerr/Sonarr integration. The question is how to request only recent and
future television episodes, with *One Piece* as the practical case.

## Answer

For a long-running series where avoiding backfill matters, add the show in
Sonarr with episode monitoring set to **Future**, keep the series monitored,
set **Monitor New Seasons** to All, and leave the initial search off. Then
monitor and search any specific recent episodes wanted. This lets Sonarr track
future episodes without a Seerr request triggering a search of the full
current season. Seerr requests whole seasons; it has no individual-episode
request control. Its Sonarr handoff marks each requested season monitored and
normally starts a search, which can include every already-aired episode in
that season. In this repository, `admin` and `viewer` requests are
automatically approved, so there may be little time to change monitoring
before that search starts.

Sonarr's **Future** mode includes episodes with no air date. Its **Recent**
mode includes episodes in the previous 90 days, plus future and undated
episodes, when the mode is applied. For a controlled recent catch-up, start
with Future and manually monitor only the desired recent episodes. Do not use
**Last Season** as a substitute for Future: it selects the latest numbered
season's known episodes, including old ones.

This is an operational recommendation inferred from the cited source behavior;
it was not exercised against a running Seerr or Sonarr instance.

## Findings and sources

### Seerr request scope and UI

Seerr's General settings say that **Allow Partial Series Requests** permits
requests for specific TV seasons and is enabled by default. If disabled, a user
can request only all unavailable seasons. The request API represents the
selection as `seasons: number[] | "all"`, and the request route rejects a TV
request with no seasons. Therefore Seerr has a season selector, not a
current-episode or current-and-future-episode selector.

- [Seerr General settings: Allow Partial Series Requests](https://github.com/seerr-team/seerr/blob/v3.4.1/docs/using-seerr/settings/general.md#allow-partial-series-requests)
- [Seerr request API type](https://github.com/seerr-team/seerr/blob/v3.4.1/server/interfaces/api/requestInterfaces.ts)
- [Seerr request route](https://github.com/seerr-team/seerr/blob/v3.4.1/server/routes/request.ts)
- [Seerr 3.4.1 request-modal season filtering](https://github.com/seerr-team/seerr/blob/v3.4.1/src/components/RequestModal/TvRequestModal.tsx#L238-L245)

The 3.4.1 request modal filters out metadata seasons with zero episodes and,
unless Special Episodes are enabled, season zero. An announced future season
that the metadata provider has not returned, or that it returns with zero
episodes, therefore cannot be selected in that UI yet. This is a UI/metadata
limit, rather than a Sonarr monitoring setting.

The Seerr maintainers' April 2026 explanation is consistent with the source:
a request for an airing season sends the entire season to Sonarr, and Sonarr
then handles episodes as they become available. It also confirms that Seerr
does not request individual episodes. This is an official project discussion,
not versioned product documentation, so it supports the interpretation rather
than replacing the source evidence above.

- [Seerr discussion #2839](https://github.com/seerr-team/seerr/discussions/2839)

### Roadmap status (reviewed 2026-09-23)

Seerr has not shipped a user-facing request control for **Future Episodes**,
**Future Seasons**, or **Latest Season + Future Seasons**. The direct
Sonarr-monitoring request remains open as [#325](https://github.com/seerr-team/seerr/issues/325)
(opened 2023-02-08); its duplicate [#1019](https://github.com/seerr-team/seerr/issues/1019)
was closed on 2024-12-19. In July 2026, a maintainer closed [#3281](https://github.com/seerr-team/seerr/issues/3281)
as a duplicate of [#332](https://github.com/seerr-team/seerr/issues/332), saying
that Future Episodes is a separate Sonarr operation that unmonitors existing
episodes and is not suitable for Seerr's request flow, which only adds
monitoring. Issue #332, the Future Seasons request, has been open since
2023-02-22 with no assignee, milestone, or linked PR. A related
[May 2026 design discussion](https://github.com/seerr-team/seerr/discussions/3087)
describes a working prototype and unresolved quota semantics; it is evidence of
exploration, not a committed roadmap or delivery promise.

The shipped feature is narrower: [PR #2071](https://github.com/seerr-team/seerr/pull/2071),
merged 2026-02-27 and present by [v3.2.0](https://github.com/seerr-team/seerr/releases/tag/v3.2.0),
added the Sonarr-service **Monitor New Seasons** setting with **All** or
**None**. It is an administrator-wide destination default passed to Sonarr for
every series request; it does not let a requester choose a show, season, or
episode policy. The 3.4.1 source still exposes only those two choices and sends
the configured value with a request.

- [3.4.1 Sonarr settings UI](https://github.com/seerr-team/seerr/blob/v3.4.1/src/components/Settings/SonarrModal/index.tsx#L1018-L1044)
- [3.4.1 request-to-Sonarr handoff](https://github.com/seerr-team/seerr/blob/v3.4.1/server/subscriber/MediaRequestSubscriber.ts#L703-L720)

There is active but unmerged work on the adjacent policy. [Issue #3152](https://github.com/seerr-team/seerr/issues/3152)
(opened 2026-06-11) asks to apply new-season monitoring only when a request
includes the latest season. Its linked [PR #3157](https://github.com/seerr-team/seerr/pull/3157)
is still open (last updated 2026-08-18): it would add a third service setting,
**Latest Season Requested**, resolving to Sonarr **All** only when the request
includes the latest regular season, otherwise **None**. That is conditional
service-level behavior, not a per-request choice or Future Episodes mode.
Likewise, [#1047](https://github.com/seerr-team/seerr/issues/1047) remains open
for a request-dialog **Request New Seasons** option; its linked [#1953](https://github.com/seerr-team/seerr/pull/1953)
only proposes per-request automatic-search control and is also open. Open issues,
discussions, and pull requests can be reprioritized or abandoned, so none is a
roadmap promise.

### What Seerr sends to Sonarr

On approval, Seerr creates Sonarr options from the request's selected season
numbers. It sends `monitored: true`, `monitorNewItems` from the Sonarr
destination, and `searchNow: !preventSearch`. For a newly added series, its
Sonarr client sets only those selected seasons to monitored and supplies
`addOptions.searchForMissingEpisodes` from `searchNow`. For an existing series,
it updates the requested seasons, re-monitors their currently known unmonitored
episodes, and calls a series search when `searchNow` is true. Thus disabling
the initial search prevents that explicit catch-up search; it does not change
the selected season's monitoring state.

- [Seerr request-to-Sonarr handoff](https://github.com/seerr-team/seerr/blob/v3.4.1/server/subscriber/MediaRequestSubscriber.ts#L703-L720)
- [Seerr Sonarr client: existing-series update and search](https://github.com/seerr-team/seerr/blob/v3.4.1/server/api/servarr/sonarr.ts#L193-L253)
- [Seerr Sonarr client: new-series POST body](https://github.com/seerr-team/seerr/blob/v3.4.1/server/api/servarr/sonarr.ts#L264-L288)

### Sonarr's two monitoring layers

Sonarr stores a monitored flag on the series, each season, and each episode.
When a season is changed through the series API, Sonarr changes the monitored
state of its episodes to match. During a metadata refresh, a newly discovered
episode inherits its season's monitored state. A series also has the separate
`monitorNewItems` setting, whose current allowed values are All and None;
Sonarr uses it to decide whether a *newly discovered season* is monitored.

- [Sonarr series API resource](https://github.com/Sonarr/Sonarr/blob/v4.0.20.3014/src/Sonarr.Api.V3/Series/SeriesResource.cs)
- [Sonarr series update propagates season monitoring to episodes](https://github.com/Sonarr/Sonarr/blob/v4.0.20.3014/src/NzbDrone.Core/Tv/SeriesService.cs#L195-L227)
- [New episodes inherit their season setting](https://github.com/Sonarr/Sonarr/blob/v4.0.20.3014/src/NzbDrone.Core/Tv/RefreshEpisodeService.cs#L146-L155)
- [New-season monitoring from `monitorNewItems`](https://github.com/Sonarr/Sonarr/blob/v4.0.20.3014/src/NzbDrone.Core/Tv/RefreshSeriesService.cs#L141-L165)
- [Sonarr monitor-new-items UI choices](https://github.com/Sonarr/Sonarr/blob/v4.0.20.3014/frontend/src/Utilities/Series/monitorNewItemsOptions.ts)

The practical distinction is:

| Control | Scope | Relevant effect |
| --- | --- | --- |
| Seerr requested seasons | Selected seasons | Chooses the seasons it asks Sonarr to monitor. |
| Sonarr series monitored | Whole series | Must remain true for ordinary RSS processing to accept releases. |
| Sonarr season monitored | Season and newly discovered episodes in it | Controls episodes added later to that season by metadata refresh. |
| Sonarr episode monitor mode | Existing known episodes | Allows a catch-up boundary such as Future or Recent. |
| Sonarr Monitor New Seasons | Later season metadata | All monitors a newly discovered regular season; None leaves it unmonitored. |

### Sonarr episode monitor modes in the current source

The current Sonarr add/edit UI offers `all`, `future`, `missing`, `existing`,
`recent`, `pilot`, `firstSeason`, `lastSeason`, special-episode toggles, and
`none`. The source retains `LatestSeason` only as an obsolete API enum value;
its implementation shares the `lastSeason` branch. There is no `next` monitor
mode in the current UI or enum.

| Mode | Current source behavior for regular episodes |
| --- | --- |
| All | Every non-special episode. |
| Future | Undated episodes and episodes whose UTC air time is now or later. |
| Missing | Every non-special episode without a file, regardless of age. |
| Existing | Episodes that already have a file. |
| Recent | Undated episodes, episodes aired within the last 90 days, and future episodes. |
| Pilot | Episode 1 of the first regular season. |
| First Season | Every episode in the first regular season. |
| Last Season / obsolete LatestSeason | Every episode in the highest season number. |
| None | No episodes. |

- [Sonarr monitor-mode UI values](https://github.com/Sonarr/Sonarr/blob/v4.0.20.3014/frontend/src/Utilities/Series/monitorOptions.ts)
- [Sonarr monitor enum, including obsolete `LatestSeason`](https://github.com/Sonarr/Sonarr/blob/v4.0.20.3014/src/NzbDrone.Core/Tv/MonitoringOptions.cs)
- [Sonarr implementation of every mode](https://github.com/Sonarr/Sonarr/blob/v4.0.20.3014/src/NzbDrone.Core/Tv/EpisodeMonitoredService.cs#L53-L173)

`Future` and `Recent` compute episode flags known at the time the mode is
applied. The season flag remains important afterwards because Sonarr gives
metadata discovered later the season's state. For a strict boundary, inspect
the episode list after applying the mode and after a metadata refresh; external
metadata can add undated or corrected episodes, and Sonarr deliberately treats
undated episodes as monitored by both modes.

The same implementation explicitly keeps the latest season monitored when
`Future` is applied to a continuing or upcoming series. `Recent` has no
equivalent rule: if the last season has no episode inside its 90-day window or
in the future, the mode can leave that season unmonitored. This makes Future
the safer starting point for an airing show after a long break.

### Search-on-add versus continued automatic grabs

Seerr's destination `preventSearch` controls the explicit search made when it
submits or updates a request. Sonarr's missing-episode search limits a
series-specific search to monitored, fileless episodes with a known past air
date. It can therefore find already released episodes in the selected season,
and is the setting that creates immediate backfill pressure.
It is separate from continuing automation. Sonarr's RSS decision specification
rejects releases when either the series is unmonitored or a release's episode is
unmonitored. Accordingly, a monitored series and episode can still be acquired
later through normal RSS/indexer processing after Search on Add was disabled,
subject to configured indexers, availability, quality rules, delays, and
download-client health.

- [Seerr Sonarr destination UI: search and new-season settings](https://github.com/seerr-team/seerr/blob/v3.4.1/src/components/Settings/SonarrModal/index.tsx#L83-L85)
- [Seerr source that maps Search on Add to `preventSearch`](https://github.com/seerr-team/seerr/blob/v3.4.1/src/components/Settings/SonarrModal/index.tsx#L254-L308)
- [Sonarr missing-episode search filter](https://github.com/Sonarr/Sonarr/blob/v4.0.20.3014/src/NzbDrone.Core/IndexerSearch/EpisodeSearchService.cs#L121-L151)
- [Sonarr RSS monitored-series and monitored-episode gate](https://github.com/Sonarr/Sonarr/blob/v4.0.20.3014/src/NzbDrone.Core/DecisionEngine/Specifications/RssSync/MonitoredEpisodeSpecification.cs)

### Practical *One Piece* workflow

1. Add *One Piece* in Sonarr with **Future Episodes** monitoring, the series
   monitored, **Monitor New Seasons: All Seasons**, and the initial search
   disabled. Check the edition and season grouping before saving; several
   similarly named series exist, and metadata providers can group anime
   seasons differently. Sonarr's current source supports these monitoring
   controls; this specific workflow was not run locally.
2. Inspect the episode list. If desired, individually monitor the most recent
   already-aired episodes and search only those. Leave old seasons and the
   remaining archive unmonitored. Avoid **All**, **Missing**, and **Last
   Season** as an initial monitoring mode for this use case.
3. Confirm that the currently airing season is monitored and that
   **Monitor New Seasons** remains All so newly discovered episodes and later
   seasons can be monitored. Check again after a metadata refresh.
4. If using Seerr for the initial request instead, select only the currently
   airing season. Disable its **Search on Add** before approval, then apply
   Future in Sonarr before searching any recent episodes. In this repository,
   changing that Seerr service setting is a global policy change and managed
   reconciliation may restore the declared value. A Seerr future-seasons-only
   request is not currently available.
5. Confirm Sonarr has working indexers and a suitable anime series type,
   profiles, and release rules. Those conditions decide whether its automatic
   processing can actually grab an accepted release.

## Validation and limits

This note reviewed tagged upstream source, the [Seerr 3.4.1 release](https://github.com/seerr-team/seerr/releases/tag/v3.4.1)
(2026-07-30), and the [Sonarr 4.0.20.3014 release](https://github.com/Sonarr/Sonarr/releases/tag/v4.0.20.3014)
(2026-09-16) on 2026-09-23. No live API call, request submission,
metadata refresh, RSS cycle, or download was run. Seerr's current `develop`
branch can change before its next release, and installed versions can differ
from the tags reviewed here. The effective episode list also depends on the
metadata provider's current season and air-date data.

## Implication for this repository

The typed Seerr integration defaults `preventSearch = false`, `syncEnabled =
true`, and `enableSeasonFolders = true`. Its selected television destination
does not override `preventSearch`, so a normal new request currently asks
Sonarr to search. The typed destination interface does not expose
`monitorNewItems`; its `extraSettings` escape hatch is the present declarative
route for that version-specific Seerr setting. No configuration change follows
from this research: use the workflow above for a per-series decision, and make
a separately reviewed policy change only if a global default is desired.

- [Typed Seerr destination defaults and extension point](../../nix-homelab/modules/integration/services/seerr.nix)
- [Selected television destination](../../hosts/nixos/desktop/local/homelab/media.nix)
