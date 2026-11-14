# Book discovery and requests

Reviewed: 2026-10-01. Scope: discovery and requests for ebooks,
audiobooks, comics, and manga alongside the desktop's existing Audiobookshelf
and Komga services. This is a source review, not a deployed or leak-tested
service. It extends the [book service survey](books-audiobooks-research.md).

## Answer

A separate request interface is useful if more than one person should ask for
missing titles and see the status. The existing readers browse **owned files**;
they do not provide one request queue for all three media types. Upstream Seerr
handles movies and TV through Radarr and Sonarr, so the current Seerr instance
cannot fill this role. [Komga features](https://github.com/gotson/komga#features),
[Seerr features](https://github.com/seerr-team/seerr/blob/develop/README.md#current-features).

**Trial BookOrbit as the single discovery and manual-request front door.** Its
request form offers E-book, Audiobook, and Comic, groups metadata results by
work, marks titles found in its own catalog, combines duplicate requests, and
provides approval, status, and manual fulfillment. The request queue works
without an acquisition source. BookOrbit explicitly recommends a read-only
mount when another server manages the same files, so it can scan the existing
Audiobookshelf and Komga media trees without gaining permission to rename or
rewrite them. Keep Audiobookshelf and Komga as the established listening and
reading clients during the trial. This is a fit judgment, not a measured
reliability ranking. [BookOrbit requests](https://bookorbit.app/book-requests/),
[library mounts](https://bookorbit.app/creating-a-library/).

BookOrbit still calls this request feature **beta**. It needs its own database,
accounts, catalog scan, and selected metadata providers. Its library view can
show books by the same author or series and similar books; smart scopes can
curate local shelves such as new arrivals. It does not make the two existing
reader databases share progress or permissions. Validate title/edition matching
and request-to-owned status before making it the sole request path.
[Request status](https://bookorbit.app/book-requests/),
[book discovery rows](https://bookorbit.app/book-details/),
[smart scopes](https://bookorbit.app/smart-scopes/).

The no-source workflow is specific: a moderator can approve a request, add
the requested file to BookOrbit's catalog by ordinary means, and close the
request against a book already in a BookOrbit library or a file in its Book
Dock. If the file is placed only in the Audiobookshelf/Komga tree, BookOrbit
must scan and match it before the request can be closed against that book.
Read-only mounts permit scanning, catalog browsing, metadata stored in
BookOrbit's database, and serving existing files. Uploads, Book Dock
finalization into those mounts, file renaming, and embedded metadata writes
need a separate writable destination or must stay disabled. The two library
write toggles alone are insufficient: the per-book **Write to File & Rename**
action bypasses them, which is why the filesystem mount must itself be
read-only. [Manual close](https://bookorbit.app/book-requests/#closing-a-request-by-hand),
[library file updates](https://bookorbit.app/creating-a-library/#7-decide-whether-bookorbit-may-change-files),
[file permissions](https://bookorbit.app/installation/#file-permissions).

Initial browsing of scanned, owned files does not require an external metadata
provider: BookOrbit reads embedded and sidecar metadata, indexes locally, and
its upstream description says no external service is required unless configured.
Requests for **missing** titles do need a metadata provider to return results.
BookOrbit lists ComicVine as its comic metadata provider and requires its API
key; the current docs do not establish equally good manga request coverage.
Test manga separately against the actual catalog rather than assuming the
Comic option finds it. [Local operation](https://bookorbit.app/what-is-bookorbit/#built-for-self-hosting),
[scan metadata](https://bookorbit.app/adding-books/),
[provider list](https://bookorbit.app/metadata/),
[request search](https://bookorbit.app/book-requests/#asking-for-a-book).

## Alternatives and boundaries

| Software | What the upstream source establishes | Fit here |
| --- | --- | --- |
| [Seerr](https://github.com/seerr-team/seerr/blob/develop/README.md#current-features) | Stable video requests and discovery; Sonarr/Radarr integration, no book/comic request backend. | Keep for movies and TV. |
| [Shelfmark](https://github.com/calibrain/shelfmark/blob/main/readme.md) | Multi-user ebook/audiobook search, approvals, Hardcover/Open Library/Google Books metadata, and optional source/download processing. Upstream explicitly excludes owned-library tracking, author/series monitoring, and future-release queues. It does not document a comic request flow. | Strong lighter choice if comics can use another queue; no unified owned-status view. |
| [BookOrbit](https://bookorbit.app/book-requests/) | One format-aware queue for ebooks, audiobooks, and comics, including manual fulfillment with no sources. | Best documented match for the requested scope, subject to a real trial. |
| [SeerrNG](https://github.com/YunoHost-Apps/seerrng/blob/main/README.md) | Independent Seerr fork adds book, audio, comic, and other categories; book dispatch needs a Bookshelf/Readarr-compatible service, and comics route to Mylar3, Kapowarr, or BackIssue. Its [book validation guide](https://github.com/YunoHost-Apps/seerrng/blob/main/docs/using-seerr/music-and-books-alpha.md) still calls those flows alpha. | Too much additional backend and migration surface for this existing reader stack. Do not treat it as an upstream Seerr upgrade. |
| [Omnibus](https://github.com/hankscafe/omnibus) / [Kapowarr](https://github.com/Casvt/Kapowarr/blob/main/README.md) | Comic-focused discovery, collection management, and acquisition. Omnibus describes ComicVine/Metron new-release and popularity feeds plus comic requests. Kapowarr focuses on monitored volumes and automated downloads. | Evaluate separately if the comic collection needs issue monitoring; both would add another library/acquisition authority. |
| [Komf](https://github.com/Snd-R/komf) | Adds AniList, MangaUpdates and other **metadata matching** to Komga/Kavita collections. | Useful for identifying comics already owned, not a missing-title request service. |

The upstream release endpoints on the review date reported
[BookOrbit 3.2.0](https://github.com/bookorbit/bookorbit/releases/tag/v3.2.0),
[Shelfmark 1.4.0](https://github.com/calibrain/shelfmark/releases/tag/v1.4.0),
[Omnibus 1.4.5](https://github.com/hankscafe/omnibus/releases/tag/v1.4.5),
and [Komf 2.1.0](https://github.com/Snd-R/komf/releases/tag/2.1.0).
These are upstream releases, not versions built or pinned in this repository.
Package freshness alone does not validate migration, security, or user experience.
BookOrbit shipped the request automation in its September 2026 2.9 release
and changed its library editor, metadata comparison, and mixed-media covers
again in 3.2.0. That release pace and a request UI still marked beta favor a
version-pinned trial, database backup before upgrades, and a tested rollback;
it is not evidence of a security defect. [2.9.0 release](https://github.com/bookorbit/bookorbit/releases/tag/v2.9.0),
[3.2.0 release](https://github.com/bookorbit/bookorbit/releases/tag/v3.2.0).

## Discovery sources and privacy

Good discovery needs separate **catalog**, **curation**, and **availability**
signals. The format-specific request UI can search metadata and the local
catalog; it cannot infer what is “best” from format support alone. For curated
books, Hardcover publishes trending, reader lists, and personalized discovery.
Open Library offers work/edition search and subject data, with a public API
intended for low-volume human lookup. For manga, AniList provides manga
metadata and community discovery; for western comics, Metron documents series,
issue, creator, pull-list and wish-list APIs. These are optional external
services with different coverage and account/privacy costs. [Hardcover](https://hardcover.app/home),
[Open Library APIs](https://openlibrary.org/developers/api),
[AniList API](https://anilist.gitbook.io/anilist-apiv2-docs),
[Metron API](https://github.com/Metron-Project/metron/blob/master/api/README.md).

Start with local catalog shelves and **one** explicitly allowed metadata
provider, then add providers only when a real title-matching gap warrants it.
Open Library asks API clients to cache, identify their application and contact,
and stay within its rate limits; it is not a bulk metadata backend. AniList also
publishes rate and data-use limits. Hardcover requires an account/token for
Shelfmark's Universal mode, so those searches reveal queries to Hardcover.
Direct cover-image URLs can also cause the *client browser* to contact the cover
host even when the server uses a VPN. Treat a provider's terms and network route
as part of enabling it. [Open Library usage](https://openlibrary.org/developers/api),
[AniList limits](https://anilist.gitbook.io/anilist-apiv2-docs/docs/guide/rate-limiting),
[AniList terms](https://anilist.gitbook.io/anilist-apiv2-docs/docs/guide/terms-of-use),
[Shelfmark metadata settings](https://github.com/calibrain/shelfmark/blob/main/docs/environment-variables.md).

An egress block on Audiobookshelf and Komga does not cover a **new** discovery
service. If BookOrbit is deployed, its own process, DNS resolver, metadata
requests, redirects, image delivery, PostgreSQL connection, and browser requests
need a separate route audit. Configure loopback binding and the existing private
HTTPS access policy; keep registration, third-party plugins, download sources,
email and outbound sync disabled for the manual-request trial. A BookOrbit source
plugin runs with access to its database, library and encryption key. Its docs
allow file-backed secrets and default the Cloudflare analytics CSP allowance to
false. These controls reduce exposure; they cannot promise that no provider,
client, resolver, or log sees book activity. [BookOrbit request source warning](https://bookorbit.app/book-requests/),
[installation and secrets](https://bookorbit.app/installation/),
[current network boundary](../operations/books-audiobooks-deployment.md#network-boundary).

## Validation and next decision

This review checked first-party documentation and GitHub release metadata on
2026-10-01. No BookOrbit, Shelfmark, SeerrNG, Omnibus, Komf, metadata provider,
or client was run locally. No migration, benchmark, database restore, or DNS/IP
capture was performed.

Before enabling BookOrbit for others, scan a small read-only copy of each media
tree; test EPUB, CBZ, M4B, and a multi-file audiobook; request missing ebook,
audiobook, and comic titles; verify duplicate and already-owned status; manually
fulfill one request; confirm restricted accounts cannot change media; restore
the database; and capture DNS, IPv4 and IPv6 traffic during search, idle time,
and network failure. If the beta queue or title matching does not pass, use
Shelfmark for ebook/audio requests and a separate manual comic list while
keeping the two established readers.
