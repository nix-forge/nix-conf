# Reliable Aurral requests

Reviewed 2026-10-03 against Aurral 2.9.1, Lidarr 3.1, slskd 0.26.0 and
Soularr 1.2.2. Scope is the native desktop music stack.

Use acquisition workflows only for material you have permission to download
and, where applicable, share. A catalog match, subscription, VPN or successful
import does not establish those rights. This note documents integration
behavior; it does not establish authorization for any particular recording.
See the [U.S. Copyright Office guidance on peer-to-peer files](https://www.copyright.gov/help/faq/faq-digital.html).

## Decisions

Aurral album requests go through Lidarr when that integration is enabled.
Its native slskd connection serves separate playlist, flow and track workflows;
it does not give Lidarr an automatic Soulseek fallback. Soularr supplies that
missing connection, reading monitored missing albums and skipping Lidarr's
active download queue. These boundaries are documented in the
[Aurral Lidarr guide](https://docs.aurral.org/integrations/lidarr/),
[Aurral slskd guide](https://docs.aurral.org/integrations/slskd/) and
[Soularr tagged source](https://github.com/mrusse/soularr/blob/v1.2.2/soularr.py).
Installed Aurral routes were also checked because current documentation can
describe features newer than the packaged release.

TRaSH explicitly has no Lidarr-specific guide. Apply its native storage,
permissions and downloader advice, and use Lidarr's own settings documentation
for music behavior. Video custom formats are not music quality profiles.
[TRaSH Lidarr](https://trash-guides.info/Lidarr/),
[native storage](https://trash-guides.info/File-and-Folder-Structure/How-to-set-up/Native/),
[Lidarr settings](https://raw.githubusercontent.com/Servarr/Wiki/master/lidarr/settings.md).

The managed quality profile prefers lossless but accepts high-quality lossy
releases. Aurral defaults and Lidarr's root-folder default use the same profile.
Custom artist selections remain intact. Automatic upgrades remain disabled to
avoid repeatedly reacquiring an already accepted album. Prowlarr's pinned
TorrentDownload definition repairs apostrophe searches and malformed title
separators that prevented otherwise available releases from matching.

Soulseek downloads now use separate complete/incomplete directories under the
media download tree, on the library's filesystem. Group `media`, setgid 2770
directories and a 0007 umask provide access. Lidarr import-time chmod/chown is
disabled because imported hardlinks may belong to another service. The reusable
slskd module owns matching tmpfiles permissions. Runtime hardlink validation
must run inside Lidarr's mount namespace, not merely compare host paths.

Keep the existing qBittorrent automatic management, per-service categories,
VPN interface binding, authenticated API and modest transfer concurrency.
Tracker injection stays disabled and the existing explicit seeding policy is
preserved. Lidarr's failed-download redownload setting is for Usenet; enabling
it does not repair stalled torrents.
[TRaSH qBittorrent](https://trash-guides.info/Downloaders/qBittorrent/Basic-Setup/),
[Lidarr settings](https://raw.githubusercontent.com/Servarr/Wiki/master/lidarr/settings.md).

## Worker and integration behavior

Soularr runs as a serialized, unprivileged oneshot with a 15-minute timer,
two-album batches, 30-second searches, a 45-minute runtime ceiling, 512 MiB
memory limit and low I/O priority. Its network access is restricted to the two
local authenticated APIs; slskd remains in the VPN namespace. No additional
web UI or public port is enabled. Credentials are loaded at runtime.

Use Lidarr's selected release, including its full multi-disc track count.
A transfer may be complete while its embedded release identifier refers to
an edition with a different track count. Lidarr can correctly reject that set
as incomplete. Preserve edition selection and test mismatched and matching
track counts with fixtures you are authorized to use. Do not bypass import
rejections or rewrite release identifiers merely to mark an album complete.

The package patch fails closed when queue inspection fails, bounds import
polling, respects pinned editions and skips peers for two hours after a failed
transfer. It journals enqueue intentions before the API call and reconciles
interrupted or partial attempts on restart. Only recorded transfers are removed;
own partial files are quarantined for inspection. Global transfer cleanup and
recursive deletion of shared download folders are disabled. Rejected or
uncertain enqueue outcomes stop the worker before it can start duplicate work.
[Upstream configuration](https://github.com/mrusse/soularr/blob/v1.2.2/config.ini).

Aurral receives authenticated Lidarr import webhooks using a persistent API key.
Its Navidrome integration uses a dedicated non-admin service account through
loopback-only Unix-socket bridges across the VPN namespace. Navidrome retains
read-only library access. Bootstrap validates the connections before saving.
[Navidrome security](https://www.navidrome.org/docs/usage/admin/security/).

## Verification and recovery

Focused checks cover bootstrap authentication, idempotency, API failures,
quality migration, slskd paths/permissions, queue failures, transfer ownership,
partial enqueue, restart recovery and edition selection. Package checks also
lint undefined names and exercise the installed CLI. Recorded live checks
covered hardlink creation inside Lidarr, Navidrome read access, authenticated
partial streaming and HTTP 401 responses from unauthenticated integration
endpoints. These are technical observations, not evidence of content rights.
Content authorization was not evaluated by those checks. The repeatable
procedure below requires independently authorized inputs.

The all-platform package check currently fails an unrelated contract: the
overlay exports `navidrome-plugin-audiomuseai-personal` where its platform metadata
excludes it. This was isolated by comparing exported and supported package names.
It does not prevent the music worker and service units from building.

Targeted live unit overrides are pinned with GC roots; their declarative
activation cleanup removes only overrides still matching those roots. This
avoids activating unrelated workstation changes. Configuration/database backups
are retained privately before deployment. Failed imports remain preserved and
listed in Soularr's state for diagnosis; clear a denylist entry only after its
cause is corrected.

slskd does not provide atomic consumer ownership. Preflight collision checks
and the journal protect ordinary sequential/restart cases, but independently
requesting the exact same peer/file simultaneously can still race. Aurral
album requests should continue through Lidarr; avoid starting parallel native
track downloads of an album already being acquired by Soularr. Aurral can show
its earlier torrent "not found" result during Soulseek acquisition; the import
webhook updates availability when Lidarr imports the album.

For a repeatable integration check, use authorized recordings or locally
created fixtures. Exercise edition mismatch rejection, successful import,
authenticated HTTP 206 playback and an idle worker run without new transfers.
Check that the ownership journal is empty after completed work and that the
recurring timer has a persistent `timers.target` dependency. The generated NixOS
unit declares `wantedBy = [ "timers.target" ]`.
