# Books and audiobooks service research

Reviewed: 2026-09-30. Scope: the desktop homelab's audiobook, ebook, comic,
and book request services. This note updates the book portion of the earlier
[media service survey](../../nix-homelab/docs/research/media-services.md). It is a
source review, not a deployment or a claim of leak-free runtime behavior.

## Answer

Use Audiobookshelf for audiobooks and podcasts. Its current server and mobile
clients cover per-user listening progress, offline listening, chapters, podcast
downloads, and scheduled database backups. Its ebook reader is deliberately
basic. [Audiobookshelf introduction](https://audiobookshelf.org/docs/documentation/introduction/),
[ebook limits](https://audiobookshelf.org/docs/documentation/libraries/book-library/ebooks/).

Pair it with Komga for ebooks, comics, and manga. Komga has a native NixOS
module and supports CBZ, CBR, EPUB, PDF, OPDS, Kobo and KOReader sync, multiple
users, and library restrictions. EPUB is the only ebook format in Komga's
terminology. Its latest release is maintained; the new NextUI remains beta, so
use the stable UI first. This is an operational fit judgment, not a measured
performance ranking. [Komga project](https://github.com/gotson/komga),
[supported formats](https://komga.org/docs/introduction/),
[native reader policy](../../nix-homelab/modules/optional/libraries.nix).

BookOrbit is now the most interesting unified reading service to trial for ebooks,
comics, and audiobooks. BookLore's maintainers identify BookOrbit as its successor
and say BookLore is in maintenance mode. BookOrbit documents web readers,
OPDS, Kobo and KOReader sync, OIDC, a native offline-capable iPhone and Apple
Watch app, and book requests. The native app requires BookOrbit 3.0 or later and
iOS 26; its request automation is still marked beta. Its setup adds PostgreSQL
and an application stack absent from the existing native reader modules. Start
with a small, separately owned library and test the actual clients before making
it the library authority. [BookLore transition](https://github.com/booklore-app/booklore),
[BookOrbit features](https://github.com/bookorbit/bookorbit#features),
[BookOrbit requests](https://bookorbit.app/book-requests/),
[BookOrbit installation](https://bookorbit.app/installation).

Kavita is another capable native option with EPUB/PDF/comic reading, OIDC, and
KOReader sync. The current evidence gives no compelling reason to run it beside
Komga. Revisit the choice if its reader or annotation features matter on the
actual devices. [Kavita releases](https://github.com/Kareadita/Kavita/releases).

## Current upstream state

These are upstream releases shown by each project's GitHub Releases API on
2026-09-30. They do not establish what the selected nixpkgs revision packages,
whether an update builds, or whether an existing database can migrate safely.
The desktop's pinned nixpkgs evaluation currently selects Audiobookshelf
2.36.1 and Komga 1.27.0. Keep those pins until the newer packages and their
database migrations pass the relevant builds and runtime checks.

| Service | Latest release checked | Decision relevance |
| --- | --- | --- |
| Audiobookshelf | [2.37.1](https://github.com/advplyr/audiobookshelf/releases/tag/v2.37.1), 2026-09-29 | The 2.37 series moves its server and build scripts to Node.js 24; 2.37.1 repairs mobile OIDC sessions and callbacks. Review the authentication migration introduced in 2.26 before updating an existing database. |
| BookOrbit | [3.2.0](https://github.com/bookorbit/bookorbit/releases/tag/v3.2.0), 2026-09-30 | The latest release adds an iPad layout and library management changes. Its rapid release pace calls for pinned images and tested migrations. |
| BookLore | [2.4.0](https://github.com/booklore-app/booklore/releases/tag/v2.4.0), 2026-09-19 | Upstream says maintenance mode and offers a guided BookOrbit migration. Do not start a new BookLore deployment as the long-term reader. |
| Shelfmark | [1.4.0](https://github.com/calibrain/shelfmark/releases/tag/v1.4.0), 2026-09-26 | Search and request tool for books and audiobooks; its release includes fixes for chaptered audio and Prowlarr failures. |
| Komga | [1.28.0](https://github.com/gotson/komga/releases/tag/1.28.0), 2026-09-29 | Recent NextUI work is still beta; retain the stable UI for the first deployment. File hashing and analysis can consume resources on large libraries. [Library options](https://komga.org/docs/guides/libraries/). |
| Kavita | [0.9.1.4](https://github.com/Kareadita/Kavita/releases/tag/v0.9.1.4), 2026-09-02 | Rich reading and progress features. Review paid Kavita+ features separately before treating them as part of the free deployment. |
| Calibre-Web | [0.6.27](https://github.com/janeczku/calibre-web/releases/tag/0.6.27), 2026-08-08 | Good when an existing Calibre `metadata.db` is authoritative; otherwise it adds another catalog to manage. [NixOS module behavior](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/nixos/modules/services/web-apps/calibre-web.nix). |

[Readarr's retirement notice](https://readarr.com/) says its metadata became
unusable and development stopped. Its presence in nixpkgs is not evidence of an
operational service. Keep an existing database only for recovery or migration.

## Acquisition and catalog ownership

Shelfmark is a plausible opt-in search and request front end. It supports
Prowlarr indexers and external download clients, but it is not an established
replacement for Readarr's author monitoring. Its documentation requires the
same reported download paths in Shelfmark and its download client for import.
BookOrbit offers its own request queue and acquisition path, including Torznab,
Newznab, qBittorrent, Transmission, Deluge, and NZBGet. Its request guide says
no sources ship enabled, distinguishes requester from settings privileges, and
requires path mappings. Choose one service to own each request and import path;
running both against the same writable inbox invites duplicate downloads and
competing moves. [Shelfmark project](https://github.com/calibrain/shelfmark),
[Shelfmark paths](https://github.com/calibrain/shelfmark/blob/main/docs/configuration.md),
[BookOrbit requests](https://bookorbit.app/book-requests/).

Keep media files in predictable author/book folders for Audiobookshelf. Its
scanner uses folder and embedded metadata, and moving an item between libraries
does not carry progress with it. Avoid automatic renames of an established
Audiobookshelf library until a sample migration proves matching and progress
behavior. [Audiobookshelf structure](https://audiobookshelf.org/docs/documentation/libraries/book-library/directory-structure/),
[library scope](https://audiobookshelf.org/docs/documentation/libraries/common-content/overview/).

## Privacy, security, and storage constraints

There is no configuration that can promise "no leaks of any kind." TLS and a VPN
address different observers; the VPN provider, indexer, metadata service,
podcast feed, remote user, and application logs may still learn something about
activity. The existing [media survey's route matrix](../../nix-homelab/docs/research/media-services.md#selective-vpn-policy-for-the-desktop)
explains the selective VPN boundary. The following policy is a recommendation,
not a runtime result.

| Path | Recommended control and remaining exposure |
| --- | --- |
| Reader and audiobook UIs | Bind to loopback behind the existing authenticated HTTPS entry point. Disable public sharing and registration unless deliberately used. Audiobookshelf's [public shares and RSS](https://audiobookshelf.org/docs/documentation/libraries/common-content/public-shares/) can deliver media without login. |
| Audiobookshelf login and automation | Configure OIDC with exact web and mobile redirects, test it before disabling local login, and give scripts revocable, scoped API keys. Upstream warns that a broken OIDC-only setup requires database editing to restore local login. [OIDC guide](https://audiobookshelf.org/docs/documentation/server-management/oidc-authentication/), [API keys](https://audiobookshelf.org/docs/documentation/server-management/api-keys/). |
| BookOrbit login and state | Use file-backed runtime secrets for PostgreSQL, JWT signing, and the one-time setup token. Keep local authentication until OIDC works. Its documentation allows explicit private OIDC issuers; do not enable that broadly. [Installation](https://bookorbit.app/installation), [OIDC](https://bookorbit.app/oidc/). |
| Discovery and downloads | A VPN-confined torrent client does not confine Shelfmark, BookOrbit, Prowlarr, or their own DNS. Shelfmark documents direct download, custom DNS, DoH and proxies; each may create a separate egress path. Disable unneeded sources, retain TLS certificate validation, and test every enabled source through the selected route. [Shelfmark network settings](https://github.com/calibrain/shelfmark/blob/main/docs/environment-variables.md), [existing VPN design](../../nix-homelab/docs/research/media-services.md#selective-vpn-policy-for-the-desktop). |
| Metadata and device sync | Audiobookshelf and BookOrbit contact external metadata providers when configured to match books. BookOrbit also offers outbound Hardcover, Readwise, and StoryGraph sync, plus email delivery. Only enable integrations with an accepted privacy cost. [Audiobookshelf introduction](https://audiobookshelf.org/docs/documentation/introduction/), [BookOrbit features](https://github.com/bookorbit/bookorbit#features). |
| Storage and backups | BookOrbit explicitly requires local filesystems for writable libraries, imports, app data, and PostgreSQL; it does not support SMB/NFS/FUSE/cloud mounts. Back up the database and media separately. Audiobookshelf's built-in backup omits media files and some covers. [BookOrbit storage warning](https://github.com/bookorbit/bookorbit#unsupported-storage-configurations), [Audiobookshelf backups](https://audiobookshelf.org/docs/category/server-management/). |

The current homelab already has opt-in Audiobookshelf, Komga, Kavita, and
Shelfmark modules. Audiobookshelf binds to loopback; the reader and Shelfmark
wrappers also set private listeners. Shelfmark's wrapper overrides upstream's
unauthenticated default with built-in authentication and keeps TLS certificate
validation on. These are configuration observations, not proof of live firewall
or DNS behavior. [Audiobookshelf wrapper](../../nix-homelab/modules/media/default.nix),
[optional reader wrapper](../../nix-homelab/modules/optional/libraries.nix),
[service catalog](../../nix-homelab/modules/catalog.nix).

## Validation and limits

The desktop package versions above came from `nix eval`; no build, activation,
client test, restore, egress capture, or benchmark was run for this research.
The source review used the root repository
at `88d8697a5b131bdd548a1c528ccb5461ce15d61a` and the checked-out
`nix-homelab` revision `07129f424bad216dcd0d0e5c2384156ba745dd3c`.

Before calling a deployment ready, test a sample library with EPUB, PDF, CBZ,
single-file M4B, and chaptered MP3 books. Confirm playback, progress and offline
sync on the intended devices; permissions and hardlink import; a database and
media restore; and service recovery after a missing mount. For every downloader
and metadata source that is enabled, observe DNS, IPv4 and IPv6 traffic during
normal operation and tunnel failure. Confirm the app fails closed where privacy
requires it, while local reader access remains available. A passed evaluation
cannot establish any of those runtime properties.
