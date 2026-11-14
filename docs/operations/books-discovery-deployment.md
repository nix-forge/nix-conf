# Book discovery deployment

The desktop configuration adds BookOrbit as a catalog with release
search and automatic fulfillment of **approved** requests beside Audiobookshelf and Komga. It does not replace their
libraries or reading progress. The [research note](../research/books-discovery-research.md)
explains the software choice and the request feature's beta status.

## Configured boundary

[The desktop policy](../../hosts/nixos/desktop/local/homelab/book-discovery.nix)
supplies digest-pinned BookOrbit 3.2.0 and PostgreSQL 18/pgvector images,
sealed credentials, media paths, and client access rules to the reusable
[Nix Home Lab BookOrbit module](../../nix-homelab/modules/services/bookorbit.nix).
Rootless Podman runs both inside the homelab's enforced VPN namespace.
Image pulls use that namespace too. The namespace uses the VPN resolver and
forbids host resolver IPC. The app listens on the namespace's host link and is
served only by the existing private HTTPS proxy. Its native port is not opened
on the LAN or WAN firewall. The HTTPS rule currently admits the approved home
LAN and WireGuard client CIDRs; a real phone client trial is still required.

Only the ebook/comic and audiobook folders are mounted at `/books` when
fulfillment is enabled. Host-managed bind mounts make those selected folders
writable inside rootless Podman so approved imports can be filed.
A mount-aware startup unit grants the BookOrbit account write ACLs only on those
two folders and the dedicated book intake. It verifies that the download category,
Book Dock, and libraries share a filesystem. App data and the dedicated
PostgreSQL data directory live under `/var/lib/bookorbit` with a private service
account. Eight credentials, including the database password and administrator
login, are encrypted with nix-seal. Systemd delivers them to the units as
temporary credentials; plaintext is not stored in the Nix store or persistent
BookOrbit state. OCI image storage is outside that backup tree. The app receives
only the book category of the VPN-confined qBittorrent client. Its sealed Web UI
credentials enter through systemd, and BookOrbit encrypts its stored copy. The
bootstrap checks the category save path, client connection, and hardlink import
mapping before enabling automatic grabs. It sets a minimum release score of 90,
checks imported files at 85, and leaves automatic retries and background searches
off. Requests still require a moderator's approval. The startup reconciliation connects BookOrbit's built-in Prowlarr
manager to enabled, book-capable torrent indexers carrying Prowlarr's `vpn` tag.
New Prowlarr indexers stay disabled in BookOrbit until the next reconciliation
confirms that route and category. A transient tracker rate limit during a
connection test leaves an otherwise VPN-vetted source enabled, so the site can
still accept requests. The Prowlarr API key remains a nix-seal secret;
BookOrbit encrypts its copy with the sealed request key.

BookOrbit and Prowlarr communicate through a private loopback and Unix socket
bridge. Both HTTP legs stay on this host, and neither creates a host-link egress
exception in the VPN namespace. Bootstrap verifies the live Prowlarr SOCKS5
proxy's tag and host-link endpoint before enabling sources. Prowlarr's systemd
network policy denies direct public IP egress, so losing that proxy cannot send
indexer queries through the host's ordinary route. Its host DNS path is blocked,
so indexer names must resolve through the VPN proxy. Browser access to each
service remains HTTPS. The state directory and Book Dock are in both the homelab recovery inventory and
the desktop Restic path list. The desktop currently has no configured Restic
destination, so this is not yet an off-device backup.

On a fresh database, a startup unit seeds the metadata provider policy before
the HTTPS site opens. It disables BookOrbit's default Amazon, Goodreads, and
iTunes providers and leaves Open Library enabled. The seed runs only when no
provider configuration exists, so later administrator choices persist. If the
seed fails, the HTTPS site returns 503. A second startup unit claims the first
superuser with the sealed username, email, password, and setup token, then
verifies login before opening the site. It also requires public registration to
remain disabled. It creates watched catalog libraries for
`/books/audiobooks` and `/books/books`, with audio and ebook/comic format filters.
File renaming and metadata writeback stay off. A mismatched sealed password or
failed library setup keeps the HTTPS site closed.

The proxy adds a browser content policy restricting image, font, media, and
scripted network requests to the BookOrbit origin. It also removes referrers
and retains HSTS and MIME sniffing protection. This reduces accidental browser
contacts to third-party cover hosts. A user who follows an external link still
contacts that destination. Server-side metadata searches reach providers
through the VPN, where those providers see the query and VPN exit address.
This configuration cannot promise the absence of all information disclosure.

## What the site shows

The dashboard and its **Discover Something New** shelf show books already in
BookOrbit's libraries. They are empty until files have been added and scanned;
they are not a public chart of popular titles. To look up a missing title, open
**Requests > Request a book**, select E-book, Audiobook, or Comic, enter a title
or author, and press Search. The current metadata policy enables Open Library
for that lookup. [Dashboard shelves](https://bookorbit.app/dashboard/#shelves),
[request search](https://bookorbit.app/book-requests/#asking-for-a-book).

Pressing **Request** adds a title to the queue. A moderator approves it. BookOrbit
then searches the configured Prowlarr sources and sends a high-scoring torrent to
the dedicated qBittorrent category. It imports a completed file into Book Dock,
checks that it matches the request, and files a passing ebook/comic or audiobook
into the corresponding library. A low-scoring or failed import waits for review.
Release results are visible to moderators, not ordinary requesters. Automatic
fulfillment depends on a usable source and matching release; BookOrbit does not
provide curated bestseller recommendations.
[BookOrbit's request workflow](https://bookorbit.app/book-requests/).

## First use

1. Finish the existing [book reader credential installation](books-audiobooks-deployment.md),
   then build and activate the reviewed desktop configuration from the
   desktop host. The BookOrbit units depend on the reader bootstrap, mounted
   media, the VPN namespace, and the image and signed-secret preparation units.
2. Verify `bookorbit-bootstrap.service` completed and open
   `https://bookorbit.<homelab-domain>` on the desktop. The first superuser is
   created automatically. Read its login from nix-seal or the approved password
   manager. Keep public registration disabled.
3. Before searching or scanning, open **Settings > Metadata** and verify the
   startup policy left only Open Library enabled. Review enrichment and cover
   settings before turning on any background metadata jobs. ComicVine needs a
   separate API key and should be enabled only after accepting its query
   disclosure and testing actual comic and manga matching.
4. Verify the **Audiobooks** and **Books and comics** libraries point at the
   intended folders. They are created automatically, with folder-based audio
   grouping and per-file ebook/comic grouping. Scan a small representative
   collection before a full scan. Local folder watching keeps owned status
   fresh without online enrichment. Only the two intended library subfolders
   have writable container mounts.
5. Create restricted reader accounts with **Request books** permission only.
   Give the moderator **Manage book requests**. Do not grant readers **Auto-approve
   requests**, **Download books directly**, **App settings**, or source plugin
   installation. Test a missing ebook, audiobook, and comic request. After
   approval, confirm a high-scoring release enters the `bookorbit` qBittorrent
   category and then lands in the correct library. Test **Find a release** for
   each medium; source coverage depends on the selected Prowlarr indexers.
6. The configuration already sets `homelab.desktopBookDiscovery.shared = true`
   for approved LAN and WireGuard clients. Test login and a sample request from
   each intended client before relying on that access.

## Checks before relying on the service

- Verify `podman-bookorbit.service`, `podman-bookorbit-db.service`,
  `bookorbit-metadata-policy.service`, both Prowlarr bridge services, and
  `bookorbit-bootstrap.service` have
  succeeded. The last two check the database policy and sealed administrator
  and reconcile vetted sources and the download client before the private HTTPS
  URL opens. Confirm the database has no host TCP listener. Inspect the container
  mounts: only the two book subfolders are present under `/books` and writable.
- Test EPUB, CBZ/CBR, M4B, and a multi-file audiobook, and confirm the same
  title is recognized as already owned before accepting the request workflow.
- Capture DNS, IPv4, and IPv6 traffic while idle, while searching Open Library,
  while searching Prowlarr releases, and after forcing the VPN down. No BookOrbit process or container should
  reach public destinations or the host resolver outside the VPN. Capture a
  client browser's network requests too; the server-side VPN does not protect
  browser-originated requests.
- Restore `/var/lib/bookorbit` into an isolated copy before depending on the
  request history. Test database and app updates together; PostgreSQL major
  upgrades need an explicit dump and restore, not an image tag change.

The BookOrbit image is fetched on service start, so a NixOS build verifies the
declarative units but does not prove image startup, database migration,
metadata quality, tunnel-failure behavior, or a working backup destination.

## Deployment verification

The isolated desktop build and focused configuration checks passed on
2026-10-01. After activation, BookOrbit, its database and bootstrap, Prowlarr,
Audiobookshelf, Komga, and Nginx were active with no failed units. All three
book sites returned HTTPS 200 with certificate validation. BookOrbit reported
two enabled Prowlarr sources; both passed their source tests. Representative
ebook, audiobook, and comic searches returned results through Prowlarr.

A controlled outage of the VPN SOCKS proxy made an indexer test fail. The same
source passed after the proxy restarted. The effective Prowlarr unit denies
public IP access and binds a resolver that cannot use host DNS. The BookOrbit
namespace routes IPv4 and IPv6 through WireGuard, with default-drop firewall
rules and DNS restricted to the VPN resolver. During activation, the source
checks briefly failed and the HTTPS gate returned 503; the bootstrap retried
and the site reopened once both sources passed. This verifies the tested server
path, not every possible client or future software state. Phone-side DNS,
representative playback, and an off-device restore are still unverified.

The approved-request automation policy was activated later on 2026-10-01.
Focused module and bootstrap tests passed. The live administration API reported
two enabled search sources, one healthy qBittorrent book client, automatic grabs
enabled at a 90-point release threshold, import verification enabled at 85,
and destinations for ebooks, audiobooks, and comics. Systemd's scoped host
bind mounts were writable inside rootless Podman; a temporary file hardlinked
from the intake directory into Book Dock and was removed. Both book libraries
accepted temporary probe files and were left empty. The three reading sites and
the BookOrbit Requests page returned HTTPS 200 with valid certificates from the
desktop. The MacBook also reached BookOrbit over HTTPS. The VPN namespace still
had default-drop input, forward, and output rules, a WireGuard default route
for IPv4 and IPv6, and DNS restricted to its VPN resolver. A representative
approved download and file import, client-side DNS behavior, a forced tunnel
failure, and an off-device restore have not yet been tested.
