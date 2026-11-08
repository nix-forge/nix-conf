# Desktop storage operations

Runtime modules live under `hosts/nixos/desktop/local/storage/`. The desktop
uses the encrypted Disko layout and has one local Restic destination on the
external homelab HDD. An independent off-site or rotated destination remains
to be provisioned.

## What 3-2-1-1-0 means here

| Requirement | Operational evidence |
| --- | --- |
| 3 copies | Working data and at least two independent Restic repositories |
| 2 media types | Source SSDs plus a different backup medium, such as an external HDD |
| 1 off-site | A destination physically outside the source location |
| 1 offline or immutable | A disconnected rotated copy or retention enforced outside this desktop's authority |
| 0 recovery errors | Recent successful backups, full repository reads, verified sample restores and a real application recovery drill |

Snapshots on the source filesystem do not count as another backup copy.
Two directories on one external disk do not have independent failure domains.
An ordinary second SSD inside the desktop is also insufficient for this policy.
The offline copy can also be the off-site copy; those are properties rather than
additional mandatory copies.

These terms follow [Veeam's 3-2-1-1-0 guidance](https://www.veeam.com/blog/3-2-1-rule-for-ransomware-protection.html).
Zero means no unresolved errors in the stated checks, not a guarantee against
all future loss. A sample restore cannot prove every application is recoverable.

## Provision destinations

A practical target is an encrypted Restic repository on a rotated external HDD
and a separate off-site repository. Keep one rotated copy disconnected between
runs. For remote immutability, enforce retention using independent administration
and credentials that this workstation does not hold.

An illustrative host-local configuration is:

```nix
{
  hardware.storage.encryptedRoot.backup.destinations = {
    rotated = {
      repositoryFile = "/run/backup-secrets/rotated-repository";
      passwordFile = "/run/backup-secrets/rotated-password";
      requiredMounts = [ "/mnt/backup" ];
      medium = "hdd";
      failureDomain = "rotated-disk";
      protection = "offline";
      maxAgeHours = 192;
      maxVerificationAgeDays = 14;
    };
    remote = {
      repositoryFile = "/run/backup-secrets/remote-repository";
      passwordFile = "/run/backup-secrets/remote-password";
      environmentFile = "/run/backup-secrets/remote-environment";
      medium = "object-storage";
      failureDomain = "remote-provider";
      offsite = true;
    };
  };
}
```

These paths are placeholders for private runtime files, supplied through the
[sealed-secret integration](../secrets.md) or provisioned manually with root ownership
and mode `0600`. The repository file contains the URL or absolute directory.
Do not place a password, provider credential or private endpoint in a Nix string.
Keep backup decryption credentials in independent recovery storage as well.

Configure the external filesystem mount separately using a verified UUID. Local
repositories must be below a configured `requiredMounts` mount point. The guard
rejects a missing mount or a repository on the source filesystems. It cannot
prove that another partition is on a different physical drive; verify that before
assigning its failure domain and medium.

`protection = "immutable"` does not create object locking, and `"offline"` does
not disconnect hardware. Verify retention and deletion behavior with the actual
backend before asserting either. Restic's mutable lock objects need a compatible
backend policy. Do not apply blanket object locking without a tested design.

Repositories are never initialized automatically. After provisioning and checking
the selected endpoint, explicitly initialize each with its installed wrapper:

```sh
sudo restic-desktop-rotated init
sudo systemctl start restic-backups-desktop-rotated.service
sudo systemctl start desktop-backup-verify-rotated.service
```

The wrapper receives the same private credential files as the service. Confirm
an external disk is mounted before running wrapper commands directly; the guard
belongs to the scheduled services and `desktop-backup-check`.

No scheduled workstation job prunes old backups. An independent administrator
must maintain retention and repository capacity, especially for append-only or
immutable storage. Choose retention against available space and recovery needs,
test it on a disposable repository, and preserve protected recovery points.
A reasonable starting retention window is daily copies for a week, weekly copies
for a month and monthly copies for six months, subject to the backend's enforced
retention minimum.

## Check recovery, not just backup completion

Run:

```sh
desktop-backup-check status
sudo systemctl start desktop-storage-health.service
desktop-storage-status
```

If verification reports a repository lock, first check that no Restic process
is still using that repository. For an abandoned lock, run
`sudo restic-desktop-homelab unlock`, then start
`desktop-backup-verify-homelab.service` again. Do not force-remove a lock held by
an active backup or check. Restic documents [manual unlock for interrupted
operations](https://restic.readthedocs.io/en/stable/077_troubleshooting.html).

With no destinations, status reports missing protection. A configured topology
also stays incomplete when backups, integrity reads, sample restores or recovery
drills are missing or overdue. Failed recent jobs must be resolved even when an
older success remains within its freshness window.

Scheduled verification reads all repository data with `restic check --read-data`,
then restores the stable random canary with `restic restore --verify` and compares
its bytes. This checks data availability, decryption and an actual restore path.
See [Restic repository checks](https://restic.readthedocs.io/en/stable/045_working_with_repos.html#checking-integrity-and-consistency)
and [verified restores](https://restic.readthedocs.io/en/stable/050_restore.html).
Full reads can incur cloud download charges; choose the verification schedule
against the recovery requirement and provider terms.

At least every 90 days, restore representative important documents and actual
application data to a separate location. Open the files or start an isolated
restored application. Check ownership, ACLs, required credentials and application
consistency. Record the successful drill only after performing it:

```sh
sudo desktop-backup-check record-recovery-drill rotated
```

The receipt records an operator attestation. It does not perform that drill.
Disconnect the rotated medium after its backup and verification complete.

## Coverage and snapshots

The local homelab destination backs up desktop files weekly on Saturday at
03:00, with up to 30 minutes of timer jitter. Home, `/etc`, `/var/lib`, `/srv/data`
and application uploads remain covered. Generated dependencies, development
virtual environments, compiler caches and known package-build downloads are
excluded; source edits, Git objects, proposals and check receipts remain covered.
File recovery can therefore be up to a week behind the working copy.

A separate daily job at 05:00 creates online SQLite backups and matching-version
PostgreSQL logical exports, including cluster roles, then copies the completed
exports to the encrypted repository. Application writers remain running. A failed
export preserves the previous complete generation and prevents a partial backup.
Storage health checks the daily job and alerts if its successful repository copy
is more than 48 hours old. Full repository verification and the restore canary run
monthly, on the first day. Existing repository snapshots are retained.

The file set also excludes snapshot histories, container engines and libvirt
state. Games themselves are regenerable; saves under home remain included. Save
data stored inside a game installation must be moved into covered storage or
explicitly added to backup paths.

Live database files need application-consistent exports. VM disk images, firmware,
vTPM state and persistent container volumes need the separate cold backup path;
the weekly file job is not evidence that those workloads are recoverable.

The manual `desktop-backup-cold-<destination>` service captures `/etc/libvirt`,
all of `/var/lib/libvirt`, Docker/containerd state and every configured normal
user's rootless Docker directory. It also restores a canary from that separate
backup set.
Missing application directories are skipped. Add custom VM disk locations and
container bind-mounted data to `backup.coldPaths` when they are introduced.

Run this from the physical console during an attended maintenance window. Verify
root console authentication and recovery media first. Stop VMs and applications
cleanly, enter `rescue.target`, and ensure user managers, Docker, containerd and
VM processes are stopped. Rescue mode ends the desktop and remote sessions.
Keep required data mounts and the external backup disk mounted. Start networking
manually if the selected repository requires it. Then run:

```sh
systemctl start desktop-backup-cold-rotated.service
systemctl status desktop-backup-cold-rotated.service
```

The service refuses multi-user operation and checks for application writers
before and after capture. It does not stop workloads automatically. Return to
normal operation only after the job completes. Full status requires a cold
backup and sample restore within `maxColdAgeDays`, which defaults to seven days.
That recovery window is separate from the daily file backup window. An empty
initial application set still needs its first checked cold capture to establish
coverage; setup does not assume there are no important workloads.

For a recovery drill, restore a `desktop-cold` snapshot into an isolated directory,
then recover the application or VM with its disk, definition, firmware and vTPM
state together. Never overwrite a live VM's backing files with a restore. Test
application startup before recording the drill.

Snapper takes independent hourly snapshots of home, general data and work.
Hourly cleanup normally keeps up to 24 hourly, 7 daily and 4 weekly snapshots.
When filesystem free space drops below 20%, range limits allow cleanup to remove
more old timeline snapshots, down to zero subject to Snapper's minimum age.
This shortens recovery history under pressure; it cannot guarantee free space
when live data fills the filesystem. This free-space policy needs no quotas.
[Snapper cleanup rules](https://github.com/openSUSE/snapper/blob/master/doc/snapper.xml.in)

Each normal user's home cache and nested container state, plus the separate VM
and games subvolumes, are outside these histories. Snapshot directories are
private to root, so recovery uses `sudo`. No automatic root rollback or Btrfs
quota subsystem is enabled.

```sh
sudo snapper --config home list
sudo systemctl start desktop-snapshot-home-timeline.service
sudo systemctl start desktop-snapshot-home-cleanup.service
```

Restore selected files from a known snapshot after inspecting it. A NixOS boot
rollback changes the system generation; it does not rewind home or application
databases.

## Drive roles and subvolume boundaries

The second internal SSD is a shared data drive. Its games mount exposes only
one subvolume, rather than the whole drive.

| Drive | Subvolume or mount | Intended contents |
| --- | --- | --- |
| System SSD | `/`, `/home`, `/nix`, `/var` and separate cache, log and container subvolumes | Operating system, home files, applications and service databases |
| Data SSD | `@data` at `/srv/data` | General durable data |
| Data SSD | `@work` at `/srv/data/work` | Working projects and other valuable work data |
| Data SSD | `@games` at `/mnt/games` | Game libraries |
| Data SSD | `@vms` at `/var/lib/libvirt/images` | Virtual machine disks |
| External HDD | `/mnt/homelab`, with nested media and backup subvolumes | Media downloads and libraries, and the local backup repository |

Btrfs subvolumes have independent directory trees and snapshot boundaries, but
share their filesystem's free space. `df` therefore reports the same used and
available capacity for each data-SSD mount. That does not mean VM disks or work
files are stored inside the games directory. No per-subvolume capacity limits
are configured. [Btrfs subvolumes](https://btrfs.readthedocs.io/en/latest/btrfs-subvolume.html)

Music services derive their mount dependencies from
`homelab.storage.requiredMounts`, and directory preparation waits for
`homelab-storage.service`. Their media belongs under the configured homelab
media root. An old media directory under `/mnt/games` is not part of the current
layout. Inspect it before migrating or removing anything, and stop any writer
before moving its data.

## Steam library on the data SSD

The separate games subvolume is mounted at `/mnt/games` on the encrypted data
SSD. The roughly 1.9 TiB filesystem capacity is shared with data, work and VM
subvolumes. In Steam,
open **Settings → Storage**, add a drive, and select `/mnt/games` as the library
root. Steam stores its `steamapps` content there. The default library under
home remains on the smaller system SSD. The data preparation service checks
that the data mounts are present before making `/mnt/games` writable by the
local `users` group. Do not place games on `/mnt/homelab`; that external media
disk is mounted with `noexec`.

New VM images in the encrypted layout retain Btrfs CoW, checksums and compression.
The generated libvirt pool explicitly enables CoW because libvirt otherwise
tries to disable it on Btrfs. Reconciliation preserves an existing pool's UUID
and updates its persistent definition without stopping active guests. An already
active pool takes the updated policy on its next start. The mounted image
directory has inherited NOCOW cleared before libvirtd starts; existing image
files still need an attended cold copy to regain checksums. See the
[migration guide](disko-desktop-migration.md) and
[libvirt pool feature documentation](https://www.libvirt.org/formatstorage.html#features).

## Health and recovery boundaries

The system polls capacity, Btrfs device error counters, failed storage services
and backup freshness. It warns at 80% usage. A desktop notification appears when
warnings change, and SMART events have their own notification path. A missing
data drive cannot stop home snapshot creation or cleanup. Its scrub job requires
the actual mount, so it cannot silently scrub root instead. The ordinary backup
job does require the data drive; a failed backup exposes missing source data
instead of issuing a complete-backup receipt for a partial capture.

Review `journalctl -u desktop-storage-health` and the relevant failed service.
Resolve full disks and checksum errors before deleting the only useful recovery
point. Metadata DUP can repair a damaged metadata copy on one drive; data SINGLE
cannot repair file contents from another local copy. Restoring verified backups
remains necessary for unrecoverable data damage.

Encryption protects a powered-off machine. An unlocked or suspended system has
keys in memory, and a compromised running account can access its available data.
Use the screen lock and shut down for a stronger offline boundary. This desktop
currently disables suspend through its existing compatibility policy. Hibernation
is also disabled because swap is randomly encrypted each boot.

## Shared media and backup disk

The intended desktop homelab deployment uses a 4 TB external HDD for
home-server media and a separate backup subtree. Provision it as a GPT data
partition containing LUKS2 and a single-device Btrfs filesystem. Btrfs uses data
SINGLE, metadata DUP, xxhash checksums, `compress=zstd:1`, `noatime`, and
`nodiscard`. Data checksums and monthly scrub detect damaged file data, but a
single data copy cannot repair it; recovery still requires an independent
verified backup. Metadata DUP is local resilience, not another backup copy. See
[Btrfs checksumming](https://btrfs.readthedocs.io/en/latest/Checksumming.html),
[scrub behavior](https://btrfs.readthedocs.io/en/latest/btrfs-scrub.html), and
[single-device profiles](https://btrfs.readthedocs.io/en/stable/mkfs.btrfs.html).

The filesystem mounts at `/mnt/homelab` as an optional, on-demand systemd
automount with `nodev`, `nosuid`, and `noexec`, so its absence does not delay or
fail boot. Do not add an idle-unmount timeout: long-running downloads, media
indexers, and filesystem watchers need a stable mount. Do not enable global
NOCOW or autodefrag: NOCOW also loses data checksums and compression, while
defragmentation can unshare snapshot or reflink extents. Already-compressed
media is skipped by Btrfs's normal compression heuristic.

The external disk has its own [Disko layout](../../hosts/nixos/desktop/local/storage/homelab-disk-layout.nix).
It is separate from the internal SSD layout, so the internal install command
cannot select it. Disko creates `@homelab` with nested `media` and `backups`
subvolumes. Before enabling the mount, identify the external whole disk by its
verified `/dev/disk/by-id/usb-` path and make sure any data needed from it is backed
up elsewhere. The following commands destroy its existing LUKS volume and all
data on that USB disk. Run them at the physical console so Disko can request a
new recovery passphrase. Disko has separate `destroy` and `format` modes; it
has no `destroy,format` mode without mounting the filesystem afterward.
Before typing `ERASE-USB`, confirm that the resolved path is the intended USB
whole disk, not a partition or either internal SSD.

```sh
(
set -e
lsblk -o NAME,PATH,TYPE,SIZE,MODEL,FSTYPE,PARTLABEL,MOUNTPOINTS
read -r -p 'Verified external whole-disk by-id path: ' homelab_disk
readlink -f -- "$homelab_disk"
test "$(lsblk -dn -o TYPE -- "$homelab_disk")" = disk
test "$(lsblk -dn -o TRAN -- "$homelab_disk")" = usb
read -r -p 'After checking the resolved path and model, type ERASE-USB: ' confirmation
test "$confirmation" = ERASE-USB
staging=$(mktemp -d)
trap 'rmdir -- "$staging"' EXIT
sudo nix run github:nix-community/disko/725ea35e410ad83be4931d1bff7e090eacaf3563 \
  -- --argstr homelabDisk "$homelab_disk" --root-mountpoint "$staging" \
  --mode destroy \
  hosts/shared/local/installers/homelab-disko.nix
sudo nix run github:nix-community/disko/725ea35e410ad83be4931d1bff7e090eacaf3563 \
  -- --argstr homelabDisk "$homelab_disk" --root-mountpoint "$staging" \
  --mode format \
  hosts/shared/local/installers/homelab-disko.nix
)
```

The private staging directory keeps Disko's pre-format unmount step away from
live mounts below `/mnt`. The installed host imports this Disko layout and
unlocks the HDD with a separate key stored on encrypted root. Keep and test the
recovery passphrase. A new format changes the LUKS UUID; the runtime crypttab
uses the stable GPT partition label instead.

When encrypted root and the homelab HDD are both enabled, the host adds a local
Restic destination at `/mnt/homelab/backups/restic`. Its repository path comes
from a root-only file under `/var/lib/desktop-storage/keys` on the encrypted
system drive. Its password is a nix-seal secret delivered to a private runtime
file. Prepare the signed nix-seal artifact before enabling the destination;
the Nix configuration contains no password and does not initialize a repository
automatically. The regular job reads home, `/etc`, `/var/lib`, and internal
work data. Live databases still need consistent exports or an attended cold
capture. The job omits Codex temporary files, Trash, caches, and the
backup key directory. It does not copy `/mnt/homelab/media` onto the same HDD.
The repository file contains the single line `/mnt/homelab/backups/restic` and
must be owned by root with mode `0600`; its parent directory must be root-only.
Keep the sealed Restic password ciphertext and independent administrator or
recovery identity available for reinstall. Check that
the HDD is unlocked and actually mounted before initializing or opening the
repository. After installing the files, run
`sudo restic-desktop-homelab snapshots` and a checked backup and restore before
relying on the schedule.
Scheduled file backups emit JSON status once per minute, followed by a snapshot
summary. The shared bulk lock keeps them separate from memory-intensive builds;
a waiting build is not evidence that the backup failed. Diagnose long runs using
processed counts, stored bytes, cgroup pressure, and the current snapshot ID.
The repository index needs memory even after source exclusions are corrected.
Check systemd drop-ins as well as the Nix declaration: an obsolete resource or
command override can silently replace the generated policy after a reload.
See [backup performance research](../research/restic-backup-performance-research.md).

The destination records `protection = "none"` and `offsite = false` because an
always-connected HDD cannot provide either property. Important media needs a
copy on another device or at another location.

`/mnt/homelab` is the external drive's stable path. `/srv/data` is a separate,
encrypted internal NVMe filesystem. Do not treat the two paths as interchangeable.

`nix-homelab` owns reusable media service policy. This repository owns the actual
mount, host resource policy, nix-seal declarations and backup destinations. The
consuming host must set `homelab.storage.rootDir` beneath the existing disk's
mount and list the mount itself in `homelab.storage.requiredMounts`. Keep
downloads and libraries on the same filesystem for hardlink imports. Keep
application databases on the system SSD and back up consistent exports.

The desktop selects:

```nix
homelab.storage = {
  rootDir = "/mnt/homelab/media";
  requiredMounts = [ "/mnt/homelab" ];
};
```

Keep the media and backup subvolumes separate. Verify the HDD mount and
permissions before moving service data or restoring from backup.

Store data by durability and access pattern:

| Data | Location | Backup policy |
| --- | --- | --- |
| Service databases, configuration, accounts, and qBittorrent resume state | Native `/var/lib/<service>` paths on the system SSD | App-consistent backup; these are small and irreplaceable |
| Rebuildable thumbnails, caches, and transcodes | Native `/var/cache` or service cache paths on the SSD | Exclude when regeneration is acceptable |
| Incomplete downloads | `/mnt/homelab/media/downloads/incomplete` | Exclude |
| Completed torrents and Usenet downloads | `/mnt/homelab/media/downloads/{torrents,usenet}` | Retain while seeding or importing; back up only when reacquisition cost warrants it |
| Curated media libraries | `/mnt/homelab/media/library/{movies,tv,music,books,audiobooks}` | Keep an independent copy for anything important or hard to reacquire |
| Local Restic repository | `/mnt/homelab/backups/restic` | It protects against system-SSD loss, not external-disk theft, failure, or host-wide incidents |
| Future VM images, containers, and working data | `/srv/data`, `/var/lib/libvirt`, and native service state | Use consistent or cold backups to an independent destination |

Use sibling media and backup directories with separate ownership. Do not put
the backup repository inside its own source tree. Budget media growth against
backup retention before enabling automatic downloads. Directory separation
does not reserve capacity, and a mostly connected media disk cannot count as
the offline backup copy. A backup of media onto that same disk cannot recover
from failure of the disk; important media needs an independent destination.
Keep the backup subtree root-owned and never merge or reuse it as a media
directory. The media and backup trees are nested Btrfs subvolumes, so a future
snapshot of one does not retain the other's data. Downloads and libraries remain
inside the same media subvolume for hardlink imports. Start with 1 TiB of
free-space headroom for backup growth and temporary work: pause managed downloads
below 1 TiB and resume only above 1.125 TiB. Revisit the thresholds after
observing growth; they are safety headroom, not a filesystem quota.

The separate homelab unlock key lives on encrypted root. Retain and test the
recovery passphrase, and keep a protected LUKS header backup. The external disk
stays outside the internal-drive destroy/format operation.
The optional unlock behavior follows
[crypttab's `noauto` and `nofail` semantics](https://www.freedesktop.org/software/systemd/man/latest/crypttab.html).

Only the BitTorrent client uses Mullvad by default. Playback and arr managers
keep normal host networking. Credentials remain user-provided through nix-seal;
provider profiles are host configuration and must not be copied into public
documentation. Private keys, passwords, and API tokens must never enter Nix
expressions or the Nix store.
The reusable service examples and migration notes live in the companion
[nix-homelab repository](https://github.com/IanHollow/nix-homelab). Update that
link after the organization transfer.

The desktop media profile uses the homelab HDD. Keep an independent recovery
destination for important media and application state. Check missing-disk
refusal, same-filesystem hardlink imports, VPN outage and recovery behavior,
media playback, and a representative restore after service changes.
