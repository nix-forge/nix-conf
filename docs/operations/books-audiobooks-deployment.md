# Books and audiobooks on the desktop

The desktop uses Audiobookshelf for audiobooks and Komga for EPUB, PDF, CBZ and
CBR files. The [research note](../research/books-audiobooks-research.md) records the service
choice and current upstream versions. Audiobookshelf listens on port 13378
because another desktop application uses port 8000. Komga listens on its private
port 25600. Both sit behind the existing LAN and approved WireGuard HTTPS
gateway, with separate administrator and reader accounts.

The discovery and approved-request workflow is documented in the
[BookOrbit deployment guide](books-discovery-deployment.md).

## Shared library flow

An approved BookOrbit request can be downloaded and filed automatically. You can
also add a permitted audiobook under `<MEDIA_LIBRARY>/audiobooks`, or an EPUB,
PDF, CBZ, or CBR under `<MEDIA_LIBRARY>/books`. The same file then appears in
BookOrbit's catalog and in its specialist reader after their scans. BookOrbit
watches both folders; Audiobookshelf uses its library file watcher; Komga scans
the book folder on startup and every hour. The desktop policy owns Komga's
scan interval and reconciles it for an existing library as well as a new one.
Komga's [library scan settings](https://komga.org/docs/guides/libraries/)
describe the supported intervals. Scans do not transfer BookOrbit requests or
copy files between applications.

Use BookOrbit to find and request a title, Audiobookshelf to listen, and Komga
to read ebooks and comics. The dashboard groups all three under Reading. Each
application keeps its own accounts and progress. BookOrbit's
[Audiobookshelf migration](https://bookorbit.app/migration) is a one-time import,
so it does not keep playback positions synchronized with Audiobookshelf.

The media roots are `<MEDIA_LIBRARY>/audiobooks` and `<MEDIA_LIBRARY>/books`.
Keep one book or series per folder. Both applications can read the media and
write their own state; they cannot change the library. Audiobookshelf's reader
can download audiobooks for offline listening. Komga's reader can stream pages
and download files for a compatible OPDS client. External metadata matching,
podcast downloads and Kobo store sync are unavailable because the reader service
units allow loopback traffic only. BookOrbit's separate acquisition path uses the
VPN-confined qBittorrent client and scoped write access to the two book roots.

## First activation

Four login names and four distinct random passwords were encrypted with
`nix-seal secret bootstrap complete` and saved as ciphertext under the desktop's
local secrets directory. Each account has a `-username` and `-password` field:

- `homelab-books-audiobookshelf-admin-*`
- `homelab-books-audiobookshelf-reader-*`
- `homelab-books-komga-admin-*`
- `homelab-books-komga-reader-*`

The authorizer key and plaintext values stay outside this repository and
command line arguments. Follow the [nix-seal preparation workflow](../secrets.md)
to sign and install the runtime artifacts before switching the desktop. The
repository ciphertext files make the book services eligible for activation.
An authorized administrator host can use its root SSH key to install the
prepared artifacts into the desktop's root-owned cache. Review the dry run and
verify the signed artifacts before switching.

After activation, `homelab-integrate-audiobookshelf.service` creates its
Audiobooks library and sealed reader account. `homelab-books-bootstrap.service`
claims Komga, creates the Books library and a restricted reader, and tests
both backends before marking their HTTPS sites ready. Until that completes,
the proxy returns HTTP 503 for both book sites. Restarting either backend
withdraws the readiness marker and reruns bootstrap. The site names are
`audiobookshelf.<DOMAIN>` and `komga.<DOMAIN>` under the existing private HTTPS
policy. Read the login names from the deployed nix-seal credentials or the
approved password manager; they are not embedded in the Nix store.
Komga's reader password is reconciled on bootstrap. Rotate its administrator
password in Komga and in nix-seal as one planned operation; changing only the
ciphertext leaves bootstrap unable to authenticate and the site closed.

Check the services, then sign in with the reader account on a phone or browser:

```sh
systemctl status audiobookshelf komga homelab-integrate-audiobookshelf homelab-books-bootstrap
systemctl status restic-backups-desktop-<DESTINATION>
```

The existing [Bitwarden importer](../../hosts/nixos/desktop/local/homelab/credentials/homelab_to_bitwarden.py)
recognizes all four book accounts. Run it with `--dry-run` first, then
`--apply` when the deployed credentials and URLs are correct. It unlocks the
vault locally and keeps passwords out of shell arguments and terminal output.

For listening, use Audiobookshelf's web player or its companion mobile app;
download a book in the app before offline use. For reading, start with Komga's
web reader. An OPDS v2 client can use
`https://komga.<DOMAIN>/opds/v2/catalog` with the Komga reader credentials.
Reading progress behavior varies by client, so test it on the intended devices
before relying on cross-device sync. [Audiobookshelf mobile](https://audiobookshelf.org/docs/documentation/introduction/),
[Komga OPDS](https://komga.org/docs/guides/opds/).

The desktop Restic backup path list includes both book media roots, and the
homelab operations inventory includes both application state directories.
No Restic destination is currently configured, so no scheduled off-device book
backup runs yet. Add a destination, then verify its backup and a restore before
relying on progress or files. The required media mount blocks service startup
and backup work when absent.

## Network boundary

The services bind to loopback and their native ports remain closed at the host
firewall. systemd blocks public IPv4 and IPv6 destinations, replaces host DNS
with an unusable loopback resolver, and hides local resolver sockets. The HTTPS
gateway admits only the configured home LAN and approved WireGuard clients.
The two book locations disable nginx access logs to avoid recording reading
paths and client addresses during normal requests.
Application metadata searches that need the internet fail under this policy.

This configuration cannot guarantee that a client device, DNS resolver,
certificate authority, VPN provider, password vault, backup destination or
application log never reveals a hostname, IP address or book activity. Validate
live DNS, IPv4 and IPv6 traffic from the intended clients and services,
including a failed tunnel, before making a stronger privacy claim. The
[research note](../research/books-audiobooks-research.md#validation-and-limits) lists the
remaining playback, progress and restore checks.
The existing nix-seal build also warns that the tool is pre-1.0 and has not
completed an external security audit; using encrypted credentials here does not
remove that system-level assurance gap.
