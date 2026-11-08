# Free indexers and subtitle providers for the desktop homelab

Reviewed: 2026-09-21; routing and provider policy updated 2026-09-22. Scope:
free sources relevant to Prowlarr, Bazarr, and the optional Usenet downloader
in the current `nix-homelab` checkout. This is a source review, not a live
quality, uptime, or download test.

## Answer

Start with no provider accounts. For authorized public-domain media, the
[Internet Archive Prowlarr definition](https://github.com/Prowlarr/Indexers/blob/dbfe3236b8b9d30c695e35b9e9cae339c426afa6/definitions/v11/internetarchive.yml)
offers public search without a provider credential. Its catalog includes more
than one rights status, so check each item's rights. [LinuxTracker's definition](https://github.com/Prowlarr/Indexers/blob/dbfe3236b8b9d30c695e35b9e9cae339c426afa6/definitions/v11/linuxtracker.yml)
also needs no credential, but its catalog is Linux and other open-source
software, not a general movie or TV source. Neither definition establishes
Prowlarr RSS support. These are scoped recommendations based on public source
and provider descriptions, not measured search quality.

For subtitles, use Bazarr's **Embedded Subtitles** provider first when the
media already contains a subtitle track. It needs no account. For external
subtitles, [SubDL](https://subdl.com/vi/developers) offers a free account and
API key; [OpenSubtitles.com](https://blog.opensubtitles.com/opensubtitles/web/understanding-opensubtitles-websites-and-services)
offers a free account and uses account credentials in Bazarr. Both appear in
[Bazarr's supported-provider list](https://github.com/morpheus65535/bazarr),
along with Embedded Subtitles. Provider search and download limits can change;
SubDL's current developer page advertises 2,000 searches and 50 downloads per
day for its free API, while Bazarr's current SubDL provider calls the older
[v1 API](https://github.com/morpheus65535/bazarr/blob/master/custom_libs/subliminal_patch/providers/subdl.py).
Validate the effective limit in the installed version. OpenSubtitles says its
free `.com` account allows 20 subtitles per day; its old `.org` API requires
VIP access.

No reliable, continuously available free **binary Usenet server** was
established. [Eternal September](https://eternal-september.org/) is free with
registration but explicitly text-only. The [XS News test server](https://test.xsnews.com/)
offers free accounts intermittently, had zero available at review time, and
says it should not be a primary subscription. The former XS Usenet free tier
was retired; [XS Usenet says it has shut down](https://xsusenet.com/). Keep
the enabled clients' server entries disabled until a suitable server is
chosen. An NZB
indexer only finds NZB files; it does not supply the articles that a Usenet
server downloads ([SABnzbd FAQ](https://sabnzbd.org/wiki/faq)).

For a no-subscription trial, [Usenet.Farm](https://usenet.farm/) currently
offers 10 GB without payment details. Its paid prepaid block is 500 GB for
€15, but the provider says it retains frequently requested binaries using
its own algorithm; the text retention figure is not a binary retention
guarantee. [BlockNews](https://billing.blocknews.net/signup.php) currently
lists non-expiring blocks starting at 5 GB for $1.99. These are finite data
allowances, not lifetime unlimited access or a guarantee that a particular
article exists. Test one permitted NZB with a free trial before buying a block
or an NZB indexer account. A separate NZB indexer may be needed to find files,
but no paid indexer is recommended without tested results for the user's
actual catalog.

## Candidates and account requirements

| Source | Free account needed? | Use and limit |
| --- | --- | --- |
| [Internet Archive](https://archive.org/about/) | No for the reviewed Prowlarr integration | Search Archive BitTorrent items. Review the item's rights and publisher before download. |
| [LinuxTracker](https://www.linuxtracker.org/) | No for public downloads | Linux and open-source images. Verify publisher checksums; not a general media indexer. |
| [NZBIndex](https://www.nzbindex.com/api) | API documentation says a key is required; public behavior conflicts | Prowlarr implements search, but provider API docs require a key while one unauthenticated read-only probe returned JSON. No tested account flow or content-rights scope. Do not enable by default. |
| Bazarr Embedded Subtitles | No | Extracts tracks already in local media; cannot find subtitles absent from the file ([Bazarr provider UI source](https://github.com/morpheus65535/bazarr/blob/master/frontend/src/pages/Settings/Providers/list.ts)). |
| [SubDL](https://subdl.com/vi/developers) | Yes, free account and API key | External subtitle search. Keep the key in nix-seal. The provider records API usage and server request metadata under its [privacy policy](https://subdl.com/privacy). |
| [OpenSubtitles.com](https://blog.opensubtitles.com/opensubtitles/web/understanding-opensubtitles-websites-and-services) | Yes, free account | External subtitle fallback. Bazarr stores its username and password in private settings ([Bazarr configuration source](https://github.com/morpheus65535/bazarr/blob/master/bazarr/app/config.py)). The old `.org` API is not a free substitute. |
| [XS News test server](https://test.xsnews.com/) | Yes, only when an account is available | Free binary server test, currently no accounts and explicitly unsuitable as a primary service. |
| [Eternal September](https://eternal-september.org/) | Yes | Free text Usenet only; unsuitable for SABnzbd media downloads. |

The following broader public trackers have definitions in the maintained
[Prowlarr catalog](https://github.com/Prowlarr/Indexers/tree/dbfe3236b8b9d30c695e35b9e9cae339c426afa6/definitions/v11).
The table records candidates, including sources that remain unconfigured.
Host reachability has been checked for some candidates; release quality and
VPN-routed Prowlarr operation remain untested. A public catalog listing does
not establish rights to download a particular item.

| Candidate definition | Catalog role | Account | Browser challenge note |
| --- | --- | --- | --- |
| [1337x](https://github.com/Prowlarr/Indexers/blob/dbfe3236b8b9d30c695e35b9e9cae339c426afa6/definitions/v11/1337x.yml) | General, including movies, TV and music | None in definition | All listed base URLs returned Cloudflare HTTP 403 from the host; the primary URL also returned 403 through the VPN namespace. Browser solver success remains untested. |
| [YTS](https://github.com/Prowlarr/Indexers/blob/dbfe3236b8b9d30c695e35b9e9cae339c426afa6/definitions/v11/yts.yml) | Compact movie releases | None in definition | Direct connection. |
| [EZTV](https://github.com/Prowlarr/Indexers/blob/dbfe3236b8b9d30c695e35b9e9cae339c426afa6/definitions/v11/eztv.yml) | TV | None in definition | Definition mentions FlareSolverr; current challenge behavior needs a live test. |
| [Nyaa.si](https://github.com/Prowlarr/Indexers/blob/dbfe3236b8b9d30c695e35b9e9cae339c426afa6/definitions/v11/nyaasi.yml) | Anime and East Asian media | None in definition | Direct connection. |
| [LimeTorrents](https://github.com/Prowlarr/Indexers/blob/dbfe3236b8b9d30c695e35b9e9cae339c426afa6/definitions/v11/limetorrents.yml) | General | None in definition | Direct connection. |

The catalog definitions advertise anime, TV, film, music, and book categories;
category support does not prove useful results or release quality. A read-only
reachability check on 2026-09-22 found that several catalog URLs responded
over HTTPS, while every listed 1337x URL returned HTTP 403. One response
included Cloudflare's `cf-mitigated: challenge` header. These observations
do not establish that Prowlarr can validate a provider or that a browser
challenge solver will work through a selected VPN route. Keep actual provider
selection and routing in the private runtime configuration.

Public tracker listings can include mislabeled, malicious, or unlicensed
material. Review publisher and rights, and verify downloads before opening
them. A tracker being listed by Prowlarr does not imply endorsement.

Other broad engines were considered. The
reviewed [Knaben implementation](https://github.com/Prowlarr/Prowlarr/blob/12c327808314a7cae1b7301935ee10cabc19609f/src/NzbDrone.Core/Indexers/Definitions/Knaben.cs)
has no account requirement, but its [own API examples](https://knaben.org/api/v1/)
show aggregation from sites with no bounded rights or publisher scope. The
[TorrentsCSV implementation](https://github.com/Prowlarr/Prowlarr/blob/12c327808314a7cae1b7301935ee10cabc19609f/src/NzbDrone.Core/Indexers/Definitions/TorrentsCSV.cs)
also lacks such scope, and its homepage returned 404 during this review.
[BinSearch is marked obsolete](https://github.com/Prowlarr/Prowlarr/blob/12c327808314a7cae1b7301935ee10cabc19609f/src/NzbDrone.Core/Indexers/Definitions/BinSearch.cs)
in Prowlarr. None is a good automatic default for the reusable module.

## Security and repository implications

The [integrated media example](../../nix-homelab/examples/integrated-media.nix)
leaves Prowlarr indexers and Bazarr subtitle providers unselected. The desktop
loads its chosen indexers from a sealed runtime document.
Metadata requests from Prowlarr and the media managers stay on the host route.
Check each provider's rules before using the VPN route.
The private document validator requires exactly one `vpn` or `direct` route
tag per indexer; a browser challenge also requires the VPN route. Manually
added Prowlarr indexers remain outside that validation and require review.
Prowlarr, the media managers, and Seerr reach public metadata directly while
systemd denies private network destinations. qBittorrent and the indexer
proxy run in the WireGuard namespace. The optional FlareSolverr service runs
in that namespace when enabled. Bazarr uses only its embedded subtitle
provider and cannot reach public providers. [TRaSH currently calls FlareSolverr non-functional](https://trash-guides.info/Prowlarr/prowlarr-setup-flaresolverr/), but [upstream released 3.5.2 in September 2026](https://github.com/FlareSolverr/FlareSolverr/blob/master/CHANGELOG.md). Enable it only for a reviewed indexer with a matching tag. Use official HTTPS
provider endpoints, unique credentials, and nix-seal secret fields. Keep TLS
verification enabled. Avoid cookie-based integrations. Treat downloaded
torrents, NZBs, archives, and subtitle files as untrusted; test with a
permitted item before scheduling automatic searches.
[nix-homelab's integration guide](../../nix-homelab/docs/integration.md)
keeps provider registration opt-in and credential fields in runtime secrets.

## Validation and limits

The original indexer review read Prowlarr `develop` at `12c3278` and Prowlarr
Indexers at `dbfe323`, plus provider pages, on 2026-09-21. The subtitle and
Usenet review read official provider and project documentation on the same date.
On 2026-09-22, candidate definitions and public HTTPS pages were checked
again. No authenticated Prowlarr tests or downloads were made. Source support
and host reachability do not prove that the pinned Prowlarr package can connect
through the VPN route. Test each chosen provider through Prowlarr after
activation.
The 2026-09-22 VPN policy check covers proxy selection, private network
denial, and qBittorrent stopping after a download completes. It does not
establish live provider reachability.
