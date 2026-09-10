# Desktop storage operations

Runtime modules live under `hosts/nixos/desktop/local/storage/`. They provide
recovery tools, monitoring and an opt-in encrypted layout. Backup destinations
are empty by default because no external destination has been provisioned.

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
[sealed-secret integration](secrets.md) or provisioned manually with root ownership
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

With no destinations, status reports missing protection. A configured topology
also stays incomplete when backups, integrity reads, sample restores or recovery
drills are missing or overdue. Failed recent jobs must be resolved even when an
older success remains within its freshness window.

Weekly verification reads all repository data with `restic check --read-data`,
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

The daily file set includes home, `/etc`, `/var/lib`, and `/srv/data`. It excludes
snapshot histories, caches, container engines and libvirt state. Games themselves
are regenerable; saves under home remain included. Save data stored inside a game
installation must be moved into covered storage or explicitly added to backup
paths.

Live database files need application-consistent exports. VM disk images, firmware,
vTPM state and persistent container volumes need the separate cold backup path;
the daily file job is not evidence that those workloads are recoverable.

The manual `desktop-backup-cold-<destination>` service captures `/etc/libvirt`,
all of `/var/lib/libvirt`, Docker/containerd state and the configured rootless
Docker directory. It also restores a canary from that separate backup set.
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
Retention keeps 24 hourly, 7 daily and 4 weekly snapshots. Nested container state
and the separate VM and games subvolumes are outside these histories. Snapshots
share free space with current files, so retention counts do not impose a byte limit.
No automatic root rollback or Btrfs quota subsystem is enabled.

```sh
sudo snapper --config home list
sudo systemctl start desktop-snapshot-home-timeline.service
sudo systemctl start desktop-snapshot-home-cleanup.service
```

Restore selected files from a known snapshot after inspecting it. A NixOS boot
rollback changes the system generation; it does not rewind home or application
databases.

## Health and recovery boundaries

The system polls capacity, Btrfs device error counters, failed storage services
and backup freshness. It warns at 80% usage. A desktop notification appears when
warnings change, and SMART events have their own notification path. A missing
data drive cannot stop home snapshot creation or cleanup.

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
