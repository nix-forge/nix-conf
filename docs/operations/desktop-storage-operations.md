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

The desktop's `desktop-backup-cold-homelab.service` now captures its declared
native application set nightly at 03:30, with up to 15 minutes of jitter. It
briefly stops only declared application writers, timers, and dependencies;
Windows and the desktop session remain running. Activation conditions prevent
those units restarting during capture. An interrupted job retains a private
recovery journal; its independent service cleanup removes only owned guards and
resumes every unit that was originally active. Originally inactive applications
remain inactive.

The encrypted application filesystem is unmounted before its backing image is
captured. Fresh native database exports are created while related file writers
are stopped. The backup then captures application files, queue state, ciphertext,
and completed exports together. After source stability is verified, applications
resume. A full restore to private temporary storage checks every captured file,
symlink, mode, owner and group against the source manifest. Temporary plaintext
restores are removed afterward. A passing receipt establishes this dataset's
byte and metadata recovery; it does not attest an application startup or replace
independent recovery credentials.

```sh
sudo systemctl start desktop-backup-cold-homelab.service
sudo systemctl status desktop-backup-cold-homelab.service
```

`backup.coldUnits` must enumerate the complete native writer and activation set,
ordered consumers before dependencies. `coldUnmounts` declares backing-image
mounts that must be inactive. `coldPrepareCommand` provides consistent exports.
Native mode rejects legacy VM/container paths. Without a native declaration,
the generic cold service retains its attended rescue-mode guard; it never stops
VMs, user managers, or containers implicitly. Custom applications need their own
complete consistency boundary before joining an unattended backup.

For a legacy VM/container capture, use the physical console, verify recovery
access, stop writers cleanly, enter `rescue.target`, and keep required storage
mounted. Rescue mode terminates desktop and remote sessions. Start the selected
cold service only after establishing that boundary. The desktop's native set
excludes Windows and container engines. Full status requires current cold backup
and restore receipts within `maxColdAgeDays`; unavailable independent destinations
remain visible even after local recovery checks pass.

For a recovery drill, restore a `desktop-cold` snapshot into an isolated directory,
then recover the application or VM with its disk, definition, firmware and vTPM
state together. Never overwrite a live VM's backing files with a restore. Test
application startup before recording the drill.

Snapper takes independent hourly snapshots of home, general data and work.
Hourly cleanup normally keeps up to 24 hourly, 7 daily and 4 weekly snapshots.
When filesystem free space drops below 20%, range limits allow cleanup to remove
more old timeline snapshots, preserving configured floors of 2 hourly, 1 daily
and 1 weekly recovery points, subject to Snapper's classification and minimum
age. Timeline creation defers below the capacity policy's critical threshold;
cleanup still runs. This shortens recovery history under pressure; it cannot guarantee free space
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

## Capacity, collection and admission

`storage/headroom.nix` owns the desktop's available-space policy. Its typed
options render the native Nix build guard, idle collection, job admission and
health reporting. The initial system-SSD thresholds are:

| Action | Available space |
| --- | ---: |
| Start Nix collection | Below 200 GiB |
| Collection target | 250 GiB |
| Ordinary job remaining-space floor / warning | 150 GiB |
| Clear warning | 175 GiB |
| Critical warning / stop new snapshots | Below 75 GiB |
| Leave critical state | 100 GiB |

The target is best effort. Compressed/shared extents, other writers and protected
roots can prevent a collection from reaching it. A collection that restores the
trigger margin records whether the higher target was reached. Nix-reported
logical deletions and actual filesystem availability are different measurements.
No threshold is a filesystem reservation or a guarantee against exhaustion.

Only the desktop capacity policy owns automatic collection. It disables Nixd's
independent collector while retaining Determinate's daemon and other services.
Do not enable `nix.gc.automatic` or `nh` cleaning alongside it. Native build-time
collection and the conditional `desktop-storage-collect.timer` use one policy
and Nix's GC lock. The timer checks every 15 minutes, yields when another managed
workload owns the bulk lock, and respects the configured daemon RAM headroom.
A failed/no-progress scan backs off; further space loss or explicit operator
recovery can cause a new attempt. Output and receipt history are bounded.

```sh
sudo systemctl start desktop-storage-collect.service
desktop-storage-status
```

Inspect `/var/lib/desktop-storage/collection.json` and the bounded collection log
as root when collection cannot restore its margin. Retire appropriate roots or
move verified regenerable data; never delete arbitrary store paths, live task
roots or backups to silence a capacity warning.

`workstation-task` checks disk space after obtaining the execution reservation.
It combines requests by filesystem UUID, so Btrfs subvolume aliases cannot each
spend the same free bytes. An undeclared ordinary job initially budgets 32 GiB
of additional system-SSD writes. Declare expected additional peaks using existing
absolute directory paths:

```sh
workstation-task --disk-mib /=32768 --disk-mib /srv/data/work=65536 -- COMMAND ARGS
```

A refusal exits 75 before the payload. It is a failed preflight, not permission
to retry a non-idempotent job automatically. Adjust the cause and use a new
attempt key. For durable desktop submissions, the existing explicit environment
interface can retain a JSON array of declarations:

```sh
export WORKSTATION_DISK_REQUESTS='["/=32768","/srv/data/work=65536"]'
workstation-job submit --owner example-task --key reviewed-attempt-1 \
  --source IMMUTABLE_REFERENCE --profile auto --memory-mib 4096 --timeout 1200 \
  --env WORKSTATION_DISK_REQUESTS -- COMMAND ARGS
```

The disk receipt is stored beside the memory allocation receipt. Queued work
rechecks current capacity; admission is not a reservation against arbitrary
applications. New ordinary work leaves 200 GiB on the data SSD. The homelab HDD
retains its separate media headroom policy.

Use `--storage-recovery` only for explicitly space-releasing maintenance or
low-write diagnostics. It preserves the memory and execution policy while
removing the ordinary disk floor; declare any additional writes honestly.
Feedback diagnostics use this recovery admission. Do not use the flag to make an
ordinary build bypass capacity policy.

Health records Btrfs allocator headroom and emergency reserve use separately
from file sizes. A nearly full allocated block group is not itself a full
filesystem when new groups can still be allocated. Device counters distinguish
new errors, historical totals, decreased/reset counters and inspection failures.
They are never reset automatically. Keep evidence and investigate before
establishing a new baseline.

## OS and task retention

The weekly `desktop-generation-retention.timer` retains the union of the latest
10 system generations, the last 14 days, the running and booted systems, and
externally rooted systems. It recognizes activatable wrappers around a protected
system. It also pins the last booted system under its own GC-root directory.
The settled-activation check compares that same resolved system identity, so an
activatable profile wrapper around the running system does not prevent scheduled
retention. A profile pointing to different system binaries still refuses cleanup.
User profiles and unrelated task roots are not retired by this service. Existing
signed ESP limits and booted-system protection remain separate.

Review exact candidates or apply an unchanged reviewed plan:

```sh
sudo desktop-storage-retention plan
sudo desktop-storage-retention apply \
  --plan /var/lib/desktop-storage/generation-plan.json
```

A changed profile, recovery root or observed target invalidates the plan. Native
profile retirement removes rollback generations; later Nix collection can remove
their unreferenced objects. Never substitute `nix-collect-garbage -d` for this
reviewed policy.

For new regenerable dependencies and intermediates, `desktop-task-cache` creates
a private directory on a provisioned, snapshot-excluded data-SSD subvolume:

```sh
desktop-task-cache example-task
```

Use a unique owner matching the task's durable jobs. Keep source edits, frozen
inputs needed for reproducibility and required results in protected locations.
The helper does not move durable clones, active checkouts or existing task state.

Place private writable Nix stores and large build intermediates in that task cache,
for example by selecting a cache child as `workstation-nix --state`. Preserve its
receipts and required outputs externally before explicit retirement. Stores under
snapshotted home state can remain physically retained by older snapshots after
ordinary GC; deleting their live paths does not remove those snapshot references.

`desktop-task-retire --owner example-task` reviews an owner's job roots without
releasing them. Explicit completion additionally requires preserved external
results and terminal, drained native jobs:

```sh
workstation-task --bounded-memory 1 --storage-recovery -- \
  desktop-task-retire --owner example-task --complete-task \
  --preserved-result "$HOME/task-results/example-task.json" --remove-cache
```

Omit `--remove-cache` to retain the cache. Cache removal refuses symlinked trees,
unexpected ownership, nested mounts/subvolumes, results inside the cache and a
current working directory inside the cache. The queue metadata lock is retained
during explicit finalization; schedule a very large cleanup as finite maintenance.
A terminal job is not task completion. Failed/interrupted or missing executions
without proven drainage must be reconciled by their owner first. Unknown legacy
roots remain for explicit review; no age-based task cleanup runs. Recipes,
claims, receipts and native queue history remain preserved.

## Cache placement and credentials

`desktop-storage-cache-ready.service` creates `/srv/data/cache` and
`/srv/data/work/scratch` as Btrfs subvolumes only after the real data mounts are
ready. An existing ordinary directory causes refusal. These boundaries exclude
regenerable content from parent snapshots; file-backup exclusions independently
omit those paths. A directory name alone supplies neither exclusion nor quota.

File/database backup wrappers share a root-private cache per destination under
`/srv/data/cache/restic`. Temporary Restic files also use that guarded volume.
Services require readiness and never intentionally write a replacement cache
into the system SSD's unmounted fallback directory. Verification retains its
existing repository-read and restore-canary semantics. An active-cache warning
starts at 64 GiB; this is a monitored budget, not an eviction cap. Restic's
stale-directory cleanup cannot bound a frequently used repository cache.

Migrate a warm cache only while its writers are idle and the shared workload
reservation is held. Copy and check it before changing users of the cache;
verify a real backup and restore sample before retiring the old copy. Client
cache cleanup is unrelated to repository pruning. Important source data stays
on its existing storage until a separately verified migration.

Public Nix configuration contains no root-private credential includes. Root,
daemon and user credentials have separate private loading paths. The managed
root installer refuses an existing unmanaged root configuration. Normal users
receive only their own nix-seal template include, including Determinate's
`nix.package = null` Home Manager mode. Verify selected non-secret settings as
both identities; do not print complete configuration JSON or token values.
Nix-seal activation does not automatically restart an active daemon for token
rotation. Perform a deliberately idle fresh daemon start when required.

A scoped preview retains its generated tools/units with an explicit GC root.
Before retiring that preview, verify the normal system/home generations own
the installed commands, public configuration and units. Preserve live queues and
applications; normal configuration activation is separate from a package build.
The broader weekly file schedule and daily database exports remain unchanged.
Choose a shorter file recovery objective and an independent backup destination
explicitly; caches and local snapshots do not supply off-site recovery.

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
and backup freshness. Capacity warnings use the absolute watermarks below when
the coordinated capacity policy is enabled. A desktop notification appears when
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

## Investigate Btrfs integrity warnings

Device error counters persist across mounts and successful scrubs. A historical
total alone does not establish current corruption. Compare saved samples with
kernel timestamps, resolve affected inodes, inspect SMART health, and check the
latest completed scrub for each filesystem. Preserve raw evidence in a root-only
directory outside this repository. Increasing counters or an uncorrectable scrub
require investigation and recovery from a verified independent copy.

The managed Windows guest uses `cache="writeback"` and `io="threads"` for its
file-backed disks in both installation and runtime definitions. This preserves
buffered I/O and guest flush handling while retaining Btrfs data checksums.
Keep those settings when recreating a guest; changing only its live XML leaves
the declarative definition able to undo the mitigation. Direct-I/O checksum
hazards and the kernel's newer buffered-write fallback are described in
[Btrfs checksumming](https://btrfs.readthedocs.io/en/latest/Checksumming.html);
[QEMU documents cache and flush behavior](https://www.qemu.org/docs/master/system/qemu-manpage.html).
A clean host scrub cannot prove the guest filesystem or application data is
consistent; guest recovery and cold backups remain separate checks.

Only after preserving the counters and logs, confirming a completed clean scrub,
and reviewing the cause should an operator reset historical device statistics
with `btrfs device stats --reset <mount>`. Save its output and immediately run
`desktop-storage-health.service` again. New errors must alert independently of
the acknowledged history. Never automate counter resets, disable data checksums,
or use `btrfs check --repair` to silence an alert.
See [device statistics](https://btrfs.readthedocs.io/en/latest/btrfs-device.html)
and [scrub limitations](https://btrfs.readthedocs.io/en/latest/btrfs-scrub.html).

An active Btrfs swapfile causes scrub to skip its block groups. The desktop's
monthly `btrfs-scrub@-.service` reserves the shared maintenance lane and requires
six GiB of RAM beyond the swapfile's used pages plus eight GiB of free non-zram
swap before temporarily stopping the fallback swapfile. Activation is guarded
until the scrub finishes. It cancels to restore swap if available RAM falls below
three GiB or remaining disk swap below two GiB, sampling headroom every 30 seconds.
Failure and cancellation have an independent recovery action; the original swap
state resumes before success is recorded. The encrypted swap partition and zram
remain active throughout. An insufficient-capacity refusal is not a complete
scrub, and its failed unit remains visible. Never bypass the admission guard or
permanently remove fallback swap to silence a warning.

```sh
sudo systemctl start btrfs-scrub@-.service
```

A successful `/var/lib/desktop-storage/checks/root-scrub.json` records a completed
root scrub without active swapfiles. The ordinary data-volume scrub is unchanged.

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
