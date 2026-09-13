# Encrypted desktop storage and boot research

Reviewed: 2026-09-09, with an implementation review on 2026-09-10 below.
Scope: a Linux-only NixOS desktop with two unequal NVMe
SSDs, development, gaming, containers, and a future Windows VM. This is a design
recommendation based on the state before implementation. The staged implementation
and its operator steps are now described in [the migration guide](disko-desktop-migration.md)
and [storage operations](desktop-storage-operations.md). Physical migration remains
separate from configuration changes.

## Answer

Use a separate Btrfs filesystem inside LUKS2 on each SSD. Keep the operating
system and ordinary home data on the system drive, with games, VM images, and
large working data on the larger drive. Use GPT, a 2 GiB EFI system partition,
conservative Zstd compression, encrypted disk swap behind zram, local file
snapshots, and independent encrypted backups.

For daily boot, recommend measured TPM unlocking with a boot PIN, followed by
normal desktop login. This supplies a boot secret without requiring a USB key.
A YubiKey with its FIDO2 PIN and touch is a sound alternative when keeping the
unlock factor physically separate from the computer matters. Register both keys
and retain an independent recovery credential. Do not require TPM and YubiKey
interaction together unless a concrete threat justifies that extra work.

Automatic TPM unlocking can provide useful security with only the normal login
prompt. It makes the running login screen and pre-login services responsible
for resisting attacks on the original computer after it boots. Choose it only
after hardening that path and accepting the difference from requiring a boot
secret. The current autologin-then-lock arrangement is not ready for that choice.

Disko can describe the recommended disk layout. Boot trust, unlock policies,
snapshots, backups, and recovery testing need additional NixOS configuration and
attended enrollment. Complexity is worth adding for those safeguards; pooling
the drives or changing to ZFS has no demonstrated benefit for this workload.

## Findings and sources

### What the existing research gets right, and what changes

The [existing migration plan](disko-desktop-migration.md) correctly separates
formatting, passphrase recovery, Secure Boot, and TPM enrollment. The
[Secure Boot research](secure-boot-lanzaboote.md) already uses systemd initrd and
Lanzaboote's managed measured-boot integration. Retain those boundaries.

The new design differs in these respects:

- Treat both drives as Linux storage. Retiring native Windows removes the
  shared-ESP preservation requirement, but data needed from Windows still needs
  backup before deleting its partitions.
- Add a second independent LUKS2 filesystem and unlock it after root, avoiding a
  second routine disk prompt.
- Prefer dedicated encrypted swap over the old Btrfs root swapfile. Current
  Btrfs documentation warns that active swapfiles can interfere with scrub and
  balance beyond the swapfile itself.
- Add explicit snapshot, backup, maintenance, and restore policies. Creating
  `@snapshots` alone provides no automatic snapshots.
- Audit the desktop's automatic session startup before enabling unattended TPM
  unlocking. Secure Boot alone does not fix that session boundary.

Read-only local inspection found plaintext Btrfs on the system and games
volumes, an unencrypted disk swap partition, and firmware Secure Boot disabled.
The Windows firmware entry uses the system drive's EFI partition. The running
system has Linux 7.2.3, systemd 261.2 with TPM2/FIDO2 support, and a usable
`systemd-pcrlock` interface. Kernel lockdown and module-signature support are
not compiled into this running kernel. These are observations, not claims about
a future installed system.

Relevant configuration is in [filesystem declarations](../hosts/nixos/desktop/local/hardware/filesystems.nix),
[staged Disko layout](../hosts/nixos/desktop/disko.nix),
[Secure Boot policy](../modules/nixos/boot/secure-boot.nix), and
[remote-play session startup](../hosts/nixos/desktop/local/headless-remote-play.nix).

### Filesystem choice

| Filesystem | Fit for this desktop | Recommendation |
| --- | --- | --- |
| Btrfs inside LUKS2 | Compression, checksums, subvolume snapshots, reflinks, incremental replication, in-tree kernel support | Preferred balance of recovery features and integration |
| ext4 inside LUKS2 | Established, straightforward administration; fewer built-in recovery features | Best simpler alternative if compression and filesystem snapshots are not needed |
| XFS inside LUKS2 | Established large-file filesystem with reflinks | Consider for a dedicated VM workload only if measurements justify it |
| OpenZFS native encryption | Dataset management, snapshots, compression, encrypted replication | Viable, but external kernel compatibility and different boot/key integration add maintenance |
| bcachefs | Broad feature set including native encryption | Avoid for primary desktop storage in this design because integration and recovery support need more work |

Btrfs checksums normal file data and metadata. On one drive, data corruption can
usually be detected but not automatically repaired without another good copy.
Ext4 metadata checksums do not provide equivalent checksums for ordinary file
contents. [Btrfs status](https://btrfs.readthedocs.io/en/latest/Status.html),
[Btrfs checksumming](https://btrfs.readthedocs.io/en/stable/Checksumming.html),
[ext4 checksums](https://docs.kernel.org/filesystems/ext4/checksums.html),
[XFS design](https://docs.kernel.org/filesystems/xfs/xfs-self-describing-metadata.html)

OpenZFS is not excluded by roughly 30 GiB of RAM. Its kernel-version requirements
matter more on a desktop tracking recent Linux kernels. Native encryption also
leaves some pool/dataset metadata visible and uses a different key-loading path
from LUKS tokens. It may fit a future storage server, but that does not require
the desktop to use ZFS. Avoid deduplication or cache/log devices without measured
need. [OpenZFS compatibility](https://github.com/openzfs/zfs),
[ZFS encryption properties](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html),
[ZFS concepts](https://openzfs.github.io/openzfs-docs/man/master/7/zfsconcepts.7.html)

The bcachefs project now states that it is distributed outside Linux following
6.18. Older advice based on its inclusion in mainline is stale. This is an
integration concern, not a claim that its feature set is inadequate.
[bcachefs upstream](https://bcachefs.org/)

No benchmark establishes the fastest filesystem for this machine. The Btrfs
recommendation weighs useful features, existing integration, and recovery cost.

### Proposed physical layout

| Drive | Partition or layer | Purpose |
| --- | --- | --- |
| System SSD, about 1 TB | GPT, 2 GiB FAT32 ESP | Firmware-readable bootloader and signed boot artifacts |
| System SSD | 16 GiB dedicated swap partition, encrypted with a fresh random key each boot | Persistent-device overflow behind higher-priority zram; no hibernation |
| System SSD | Remaining space, LUKS2 then single-device Btrfs | Root, home, Nix, and ordinary system state |
| Data SSD, about 2 TB | GPT, LUKS2 then separate single-device Btrfs | Games, VM images, large project and media data |

The swap size is a starting capacity choice, not a performance result. Adjust it
after observing memory pressure under builds, games, and VMs. No LVM layer is
needed for this proposal. If reliable hibernation becomes a requirement, consider
LUKS2 containing LVM with separate Btrfs and persistent swap logical volumes
before finalizing partition sizes.

Keep the two filesystems independent. A combined SINGLE or RAID0 Btrfs pool has
no drive-failure redundancy and increases the recovery scope. A two-drive mirror
of unequal 1 TB and 2 TB devices offers roughly 1 TB usable for mirrored data;
using the remaining capacity separately makes the layout more involved. A mirror
improves availability, while backups recover deleted, corrupted, or stolen data.
[Btrfs profiles](https://btrfs.readthedocs.io/en/latest/mkfs.btrfs.html#profiles)

Explicitly select Btrfs data SINGLE and metadata DUP. DUP keeps two metadata
copies on the same drive and cannot survive that drive failing. Current Btrfs
creation defaults support this on SSDs; do not copy old metadata-SINGLE tuning.
[Btrfs creation](https://btrfs.readthedocs.io/en/latest/mkfs.btrfs.html)

Use separate subvolumes for `/`, `/home`, `/nix`, `/var`, and `/var/log`, then
exclude high-churn container storage and caches from ordinary file-history
snapshots. On the data drive, separate games, VM images, and valuable working
data by retention needs. Mount or bind them at stable application paths.
Subvolumes share free space, so there is no need to guess a fixed `/home` size.
Snapshots do not recursively include nested subvolumes; backup coverage must
name those separately. [Btrfs subvolumes](https://btrfs.readthedocs.io/en/latest/btrfs-subvolume.html)

Open the data volume in the normal system after root is available, using a
random keyfile protected by the encrypted system volume. Keep an independent
recovery credential for the data volume so system-drive failure does not destroy
its recovery path. Never embed that keyfile in Git, the Nix store, or a public
initrd. Mount ordering must prevent services from writing into the empty mount
point if the data drive is absent. [systemd 261.2 crypttab](https://github.com/systemd/systemd/blob/v261.2/man/crypttab.xml)

### Boot experience and security

| Unlock method | Daily interaction | Boundary and cost |
| --- | --- | --- |
| Measured TPM, automatic | Normal login only | The original computer unlocks before user authentication; security depends more on the booted login environment |
| Measured TPM with PIN | Boot PIN, then login | Recommended default compromise; adds a boot secret without carrying a key |
| YubiKey FIDO2 with PIN and touch | Insert key, enter its PIN, touch, then login | Keeps an unlock factor separate from the computer; prevents unattended cold boot |
| Strong recovery passphrase | Long passphrase, then login | Independent fallback when normal hardware unlocking is unavailable |

TPM and FIDO2 slots are alternate ways to unlock a LUKS volume. Adding a YubiKey
slot does not make an existing automatic TPM slot require the YubiKey. Choose
which alternate paths are acceptable. A TPM PIN, FIDO2 PIN, LUKS recovery
credential, and desktop login password have different purposes.
[systemd 261.2 enrollment options](https://github.com/systemd/systemd/blob/v261.2/man/systemd-cryptenroll.xml)

Use FIDO2 hmac-secret for YubiKey disk unlocking. The disabled OTP keyboard
interface is unnecessary. Enroll each key separately and test both in the actual
initrd. A FIDO application reset invalidates this use as well as web credentials.
The YubiKey releases or derives an unlock secret; the CPU handles ongoing disk
encryption, so normal reads and writes do not require USB touches. Removing the
key after boot does not relock an already mounted drive.
[Yubico hmac-secret](https://docs.yubico.com/yesdk/users-manual/application-fido2/hmac-secret.html),
[Yubico FIDO behavior](https://docs.yubico.com/hardware/yubikey/yk-tech-manual/yk5-apps-fido.html),
[kernel dm-crypt](https://docs.kernel.org/admin-guide/device-mapper/dm-crypt.html)

Keep the existing Lanzaboote architecture with systemd initrd and managed
PCR4+7 policy when using TPM unlocking. Lanzaboote measures its loader/stub in
PCR4 and verifies the referenced kernel/initrd. A generic systemd-stub signed
PCR11 recipe is a different design. PCR7 alone measures the Secure Boot policy,
not the particular NixOS generation. Adding PCR0 would bind firmware code more
explicitly but increases firmware-update recovery work.
[Lanzaboote measurements](https://nix-community.github.io/lanzaboote/explanation/measured-boot.html),
[systemd PCR definitions](https://systemd.io/TPM2_PCR_MEASUREMENTS/)

The pinned Lanzaboote install hook updates allowed measurements as boot
generations change. It supports at most eight retained generations in this mode.
Normal updates should not require routine LUKS re-enrollment, but firmware,
policy, or key changes can still require recovery. Upstream labels pcrlock
experimental and recommends a TPM PIN for attended workstations. Keep recovery
available and test updates and older generations before relying on it.
[Pinned Lanzaboote module](https://github.com/nix-community/lanzaboote/blob/7c9a54a7f87b4539ddbd8bda09a8a5f5f9361aa9/nix/modules/lanzaboote.nix),
[measured-boot setup](https://nix-community.github.io/lanzaboote/how-to-guides/enable-measured-boot.html)

Retained signed generations are recovery options, not anti-rollback protection.
Before enabling automatic TPM unlock, every allowed generation must have the
reviewed login boundary. Retire or rebuild generations containing the old
autologin policy and regenerate the allowed measurements; otherwise selecting an
older generation could restore the weaker startup path. This is an implication
of the retained-generation policy and the local session configuration.

The current remote-play setup starts a logged-in session and launches its lock
service after `graphical-session.target`. The unit does not establish that the
compositor has locked before other session services run, and it does not restart
on failure. A process-name check is not proof of a locked session. This source
inspection identifies an unproven boundary, not a demonstrated exploit. Prefer
a normal password greeter. Sunshine would then become available after login;
preserving access before local login needs a separately tested design. A boot
PIN alone does not resolve later lock failures.
[Current implementation](../hosts/nixos/desktop/local/headless-remote-play.nix)

Secure Boot verifies boot artifacts. It does not enable missing kernel lockdown
or module-signature enforcement, authenticate every mutable root-filesystem
block, or protect data from privileged malware after unlocking. Btrfs checksums
are corruption detection, not cryptographic authentication. dm-integrity or
verified read-only system images can add stronger integrity properties, with
write overhead or a different operating model. Do not introduce them without a
specific tampering threat and an end-to-end update/recovery design.
[dm-integrity](https://docs.kernel.org/admin-guide/device-mapper/dm-integrity.html),
[dm-verity](https://docs.kernel.org/admin-guide/device-mapper/verity.html),
[existing kernel caveat](secure-boot-lanzaboote.md)

### Swap, suspend, and hibernation

Retain zram with higher priority than disk swap. Encrypt disk swap because it
can contain credentials and private document contents. For this design, a random
per-boot key adds no password prompt and deliberately prevents resume of an old
hibernation image. Disko exposes this through its swap type and NixOS manages
the runtime encrypted mapping. Use a stable partition identity, not a swap
filesystem UUID that changes at each initialization. This is plain dm-crypt
with an ephemeral key, not a third LUKS container.
[Pinned Disko swap implementation](https://github.com/nix-community/disko/blob/ff8702b4de27f72b4c78573dfb89ec74e36abdf1/lib/types/swap.nix),
[pinned NixOS swap implementation](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/nixos/modules/config/swap.nix)

An active Btrfs swapfile can cause scrub and balance to skip block groups that
also contain other files. A separate swap subvolume only addresses snapshot
separation, not this maintenance problem. The current upstream documentation
specifically discourages the combination on root. Dedicated encrypted swap
avoids these Btrfs restrictions.
[Btrfs swapfile documentation](https://btrfs.readthedocs.io/en/latest/Swapfile.html)

Hibernation saves the open session to disk and powers off, useful for restoring
work after long periods without power or reducing idle electricity use. Suspend
keeps the session and encryption keys in RAM and needs continuing power. Neither
mode is currently enabled in this host's compatibility policy. Hibernation also
conflicts with its kernel-image protection policy, and mainline kernel lockdown
rejects the normal hibernation path even when swap is encrypted. NVIDIA resume
would require physical testing. Keep hibernation disabled for the first design;
ordinary shutdown is sufficient when session restoration is unnecessary.
[Local sleep policy](../hosts/nixos/desktop/local/compatibility.nix),
[kernel baseline](../modules/nixos/security/kernel.nix),
[kernel suspend-to-disk](https://docs.kernel.org/power/swsusp.html),
[kernel lockdown check](https://github.com/torvalds/linux/blob/master/kernel/power/hibernate.c)

### Performance, maintenance, and workload placement

Start with the existing `compress=zstd:1`, `noatime`, and scheduled weekly TRIM.
Permit TRIM through LUKS if allocation-pattern leakage is acceptable; this does
not reveal file plaintext. Keep Btrfs `nodiscard` with the scheduled policy so
continuous discard is not accidentally enabled as well. Compression usually
helps compressible data more than compressed game assets or video. There is no
reason to force it for every write.
[Btrfs compression](https://btrfs.readthedocs.io/en/latest/Compression.html),
[Btrfs mount options](https://btrfs.readthedocs.io/en/latest/Administration.html),
[dm-crypt discard warning](https://docs.kernel.org/admin-guide/device-mapper/dm-crypt.html)

Retain monthly scrubs and SSD health monitoring, but make failures visible. With
data SINGLE, restoring a backup is often the remedy for checksum failures.
Start free-space alerts around 20 percent and tune them with observed snapshot
growth. Avoid routine full balances, blanket defragmentation, forced long commit
intervals, or disabling barriers. Those are not general desktop optimizations.
[Btrfs scrub](https://btrfs.readthedocs.io/en/latest/btrfs-scrub.html),
[Btrfs balance](https://btrfs.readthedocs.io/en/stable/Balance.html),
[existing SSD maintenance](../modules/nixos/hardware/ssd.nix)

Keep ordinary files checksummed with copy-on-write. For Windows VM images,
measure raw images on normal Btrfs against an isolated NOCOW image directory.
Set NOCOW before creating files if selected. It sacrifices Btrfs data checksums
and compression, and snapshots can still cause later CoW writes. Do not apply
`nodatacow` as if it were an isolated per-subvolume mount option. Dedicated
ext4/XFS or logical-volume VM storage remains a later option if measurements
justify reserving capacity. Preserve VM definitions, firmware variables, vTPM
state, and guest recovery material with the VM's disk backup.
[QEMU images](https://www.qemu.org/docs/master/system/images),
[Btrfs mount semantics](https://btrfs.readthedocs.io/en/latest/btrfs-man5.html),
[existing VM research](workstation-virtualization-architecture-research.md)

Do not select Docker's Btrfs driver merely because the host uses Btrfs. Current
Engine 29 defaults to containerd's image store and overlayfs snapshotter; older
installations may retain classic overlay2. Inspect the actual installation
before changing storage backends. Back up durable volumes using
application-consistent procedures.
[Docker Btrfs driver](https://docs.docker.com/engine/storage/drivers/btrfs-driver/),
[Docker overlayfs transition](https://docs.docker.com/engine/storage/drivers/overlayfs-driver/)

Before tuning dm-crypt workqueues, measure representative Nix builds, game
loading and shader compilation, VM updates, large file writes, and responsiveness
under memory pressure. Include scrub and backups running in the background.
A cipher benchmark alone does not predict those results.

### Recovery that is usable

Use Snapper for local file history, initially on home and selected valuable data.
An initial retention policy could keep 24 hourly and 7 daily snapshots, adjusted
for change volume and free space. Give snapshot creation/pruning one owner per
subvolume. btrbk is a good alternative if Btrfs replication becomes the main
requirement; it need not run alongside Snapper on the same subvolumes.
[Snapper manual](https://snapper.io/manpages/snapper.html),
[Snapper cleanup](https://snapper.io/manpages/snapper-configs.html),
[btrbk](https://github.com/digint/btrbk)

Use NixOS generations for system configuration rollback. A root snapshot can
reference Nix store paths already removed by garbage collection; snapshots of
`/nix` can conversely retain disk space after garbage collection. Keep the Nix
store and its database coherent during recovery. Do not promise automatic
whole-system rollback from installing Snapper or adding a root subvolume.
[Nix garbage collection](https://nix.dev/manual/nix/2.26/command-ref/nix-store/gc)

Use Restic for encrypted, authenticated backups following 3-2-1-1-0: working
data plus two independent backup copies, two media types, an off-site copy,
an offline or immutable copy, and verified recovery with no unresolved errors.
See [the implemented backup policy](desktop-storage-operations.md). A backup
on the other internal SSD shares theft and administrator-error risks. Run
repository checks with periodic data reads and sample restores. Plain `check`
does not read every stored data block. Keep backup recovery material available
without needing the failed desktop.
[restic repository design](https://restic.readthedocs.io/en/stable/100_references.html),
[restic checks](https://restic.readthedocs.io/en/stable/045_working_with_repos.html),
[restic restore](https://restic.readthedocs.io/en/stable/050_restore.html)

Make backups from stable snapshots where useful, and quiesce or export databases
and VMs when application consistency requires it. Local snapshots do not survive
loss of their drive. LUKS encryption does not automatically encrypt Btrfs send
streams or the receiving server. Backup encryption and independent retention
remain necessary regardless of the source filesystem.
[btrbk transport and replication](https://github.com/digint/btrbk)

Retain tested LUKS recovery credentials for both volumes, protected LUKS header
backups, Secure Boot signing-key backups, and recovery media. An old header
backup plus a formerly valid password can still unlock the unchanged volume
key, so header backups remain sensitive after password rotation. Test restoring
from another boot environment before retiring the original data.
[Cryptsetup header backup](https://gitlab.com/cryptsetup/cryptsetup/-/blob/master/man/cryptsetup-luksHeaderBackup.8.adoc)

### What Disko can implement

The audited revision is `ff8702b4de27f72b4c78573dfb89ec74e36abdf1` from the flake
lock. The boot integration is Lanzaboote 1.1.0 at
`7c9a54a7f87b4539ddbd8bda09a8a5f5f9361aa9`.

| Requirement | Disko capability | Work outside the disk layout |
| --- | --- | --- |
| Two GPT disks, ESP, partitions | Native disk/GPT/filesystem types | Verify target identities privately and restore data |
| Independent LUKS2 containers | LUKS type, formatting arguments, generated initrd mappings | Recovery, key rotation, header backup, stage-2 data unlock ordering |
| Btrfs profiles and subvolumes | Creation arguments, mounts and subvolume definitions | Snapshots, quotas if used, maintenance and alerts |
| Dedicated randomly encrypted swap | Swap type with `randomEncryption` | NixOS creates/activates runtime mapping; verify actual boot behavior |
| LUKS containing LVM, ext4/XFS, mdraid, ZFS | Native types and upstream examples | Extra lifecycle, kernel, recovery and capacity management |
| YubiKey FIDO2 | Native `enrollFido2`, `extraFido2EnrollArgs`, `enrollRecovery` | Two-key enrollment, replacement, revocation and physical boot tests |
| TPM and Secure Boot | No complete TPM/firmware lifecycle in the LUKS type | Lanzaboote, pcrlock, sbctl, cryptenroll and firmware enrollment |
| Backups and usable rollback | No automatic policy from declaring subvolumes | Snapper or btrbk, restic, Nix generation retention and restore tests |

Sources: [GPT](https://github.com/nix-community/disko/blob/ff8702b4de27f72b4c78573dfb89ec74e36abdf1/lib/types/gpt.nix),
[LUKS](https://github.com/nix-community/disko/blob/ff8702b4de27f72b4c78573dfb89ec74e36abdf1/lib/types/luks.nix),
[Btrfs](https://github.com/nix-community/disko/blob/ff8702b4de27f72b4c78573dfb89ec74e36abdf1/lib/types/btrfs.nix),
[swap](https://github.com/nix-community/disko/blob/ff8702b4de27f72b4c78573dfb89ec74e36abdf1/lib/types/swap.nix),
[LVM example](https://github.com/nix-community/disko/blob/ff8702b4de27f72b4c78573dfb89ec74e36abdf1/example/luks-lvm.nix),
[encrypted ZFS example](https://github.com/nix-community/disko/blob/ff8702b4de27f72b4c78573dfb89ec74e36abdf1/example/zfs-encrypted-root.nix).

Native FIDO2 provisioning uses a temporary formatting secret, defaults recovery
enrollment on, and removes the temporary slot after success. It checks whether
any FIDO credential is present; it does not manage two named physical keys.
Prefer an initial tested passphrase and attended enrollment of both keys so the
recovery state is clear. `settings` configures NixOS LUKS behavior;
`extraOpenArgs` alone controls installation opens. `initrdUnlock = false` permits
host-managed later unlocking of the data volume. Legacy scripted-initrd YubiKey
options do not belong in the systemd-initrd design.
[Pinned LUKS type](https://github.com/nix-community/disko/blob/ff8702b4de27f72b4c78573dfb89ec74e36abdf1/lib/types/luks.nix),
[pinned NixOS LUKS module](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/nixos/modules/system/boot/luksroot.nix)

Disko can also describe encrypted multi-device Btrfs with creation ordering, but
support does not make pooling desirable. Its `--dry-run` builds and prints a
script path; it does not simulate a migration against the physical drives.
`destroy,format,mount` is destructive. The module exports isolated installation
and VM tests for stronger validation before physical provisioning.
[Multi-device example](https://github.com/nix-community/disko/blob/ff8702b4de27f72b4c78573dfb89ec74e36abdf1/example/luks-btrfs-raid.nix),
[CLI reference](https://github.com/nix-community/disko/blob/ff8702b4de27f72b4c78573dfb89ec74e36abdf1/docs/reference.md),
[test interfaces](https://github.com/nix-community/disko/blob/ff8702b4de27f72b4c78573dfb89ec74e36abdf1/module.nix)

## Implementation review, 2026-09-10

The two independent LUKS2/Btrfs filesystems remain a sound choice. The review
found more value in correcting snapshot access, maintenance dependencies and
inherited VM file attributes than in replacing the filesystem or adding more
formatting flags. This section records the evidence and recommendations from
the review. Implementation validation belongs in
[storage operations](desktop-storage-operations.md).

### Correctness and recovery improvements

- Give precreated `.snapshots` directories root ownership and mode `0700`.
  Declaring an empty Disko subvolume does not establish Snapper's usual private
  directory permissions. Snapper's own creation path restricts access to root;
  bypassing that path must preserve the same boundary. Historical file
  permissions can differ from current permissions, so an ordinary world-readable
  directory is not an appropriate default for file history.
  [Snapper permissions](https://github.com/openSUSE/snapper/blob/master/doc/permissions.txt)
- Require the intended mount before scrubbing an optional filesystem. Btrfs
  accepts a path inside the filesystem as the scrub target. If the data drive
  is absent, its ordinary mountpoint directory belongs to root instead. A job
  named for the data drive can therefore scrub the system filesystem and appear
  successful. Check the mount and test the missing-drive case.
  [Btrfs scrub interface](https://btrfs.readthedocs.io/en/latest/btrfs-scrub.html),
  [filesystem policy](../hosts/nixos/desktop/local/hardware/filesystems.nix)
- Retain CoW for newly created VM images in the encrypted layout. The existing
  virtualization policy enabled NOCOW, contrary to the design recommendation
  above. NOCOW also removes data checksums and compression. Clearing `C` on the
  image directory changes inheritance for new files; it does not rewrite
  existing images. Converting an existing image needs an attended cold copy into
  a normal CoW destination, with verification before replacing its original.
  [Virtualization policy](../hosts/nixos/desktop/local/security-virtualization.nix),
  [Btrfs attributes](https://btrfs.readthedocs.io/en/latest/ch-file-attributes.html)
  The pool XML also explicitly selects CoW, since libvirt otherwise attempts
  to disable it on Btrfs. Existing pool definitions are updated with their UUID
  preserved; active pools need their next start to use the new definition.
  [Libvirt pool features](https://www.libvirt.org/formatstorage.html#features)
- Separate the user's `.cache` from home history just as rootless Docker
  storage is separated. A cache subvolume avoids retaining replaceable browser,
  shader and build-cache contents in every home snapshot. Subvolume snapshots
  stop at nested subvolumes, so this deliberately excludes cache data from a
  home restore. Existing cache contents need migration before an empty
  subvolume is mounted over them.
  [Btrfs nested subvolumes](https://btrfs.readthedocs.io/en/latest/btrfs-subvolume.html#nested-subvolumes)

The revised retention policy uses hourly cleanup, `FREE_LIMIT=0.2` and timeline
ranges `0-24`, `0-7` and `0-4` for hourly, daily and weekly snapshots. Count
limits alone do not bound snapshot bytes. Snapper supports a second
cleanup pass when free space falls below `FREE_LIMIT`, provided timeline limits
are ranges with separate minimum and maximum counts. This free-space check does
not need qgroups. Limiting the space consumed specifically by snapshots through
`SPACE_LIMIT` does need quota accounting. Retaining fewer snapshots under space
pressure is a useful improvement, but it shortens local history and cannot
guarantee free space if live files fill the device. Alerts and independent backups
remain necessary.
[Snapper cleanup algorithm](https://github.com/openSUSE/snapper/blob/master/doc/snapper.xml.in),
[Snapper configuration](https://github.com/openSUSE/snapper/blob/master/doc/snapper-configs.xml.in)

Simple quotas, supported since Linux 6.7, reduce accounting overhead but do not
track shared versus exclusive space. They are not a drop-in replacement for
Snapper's exclusive snapshot accounting. Enable conventional qgroups only if
that accounting or hard subvolume limits justify the added work.
[Btrfs quota modes](https://btrfs.readthedocs.io/en/latest/btrfs-quota.html)

The ordinary Restic job intentionally requires both data mounts before recording
a complete backup. This avoids a successful receipt for a backup that silently
omitted the second drive, but an absent data drive also prevents that job from
backing up home. Keeping home backups available in that condition would require
separate source sets, receipts and restore checks. Simply removing the mount
guard would weaken the current completeness guarantee.
[Backup policy](../hosts/nixos/desktop/local/storage/backups.nix)

### Modern defaults already present

Read-only evaluation reports Linux 7.2.3, btrfs-progs 7.1, cryptsetup 2.8.7 and
systemd 261.2. The installed `mkfs.btrfs -O list-all` reports `extref`,
`skinny-metadata`, `no-holes`, `free-space-tree` and `block-group-tree` as defaults.
The last became a creation default in btrfs-progs 6.19 and needs Linux 6.1 or
newer. A newly provisioned filesystem already gets these features without
duplicating the defaults in Disko. Recovery media must support its on-disk
features; updating NixOS does not automatically convert an older filesystem.
[Btrfs creation features](https://btrfs.readthedocs.io/en/latest/mkfs.btrfs.html#filesystem-features)

Keep CRC32C unless a checksum comparison establishes a reason to change it.
It is the Btrfs default and has hardware acceleration on modern CPUs. XXHASH
offers a wider digest; SHA256 and BLAKE2 offer cryptographic-strength hashes
with different CPU and checksum-storage costs. None adds keyed authentication
to mutable filesystem data. Preserve data checksumming before considering a
different checksum algorithm.
[Btrfs checksum choices](https://btrfs.readthedocs.io/en/latest/Checksumming.html)

Keep `compress=zstd:1`. Negative Zstd levels have existed since Linux 6.15 and
trade compression ratio for speed; their availability does not establish a
benefit for this workload. Compression mount options apply across the filesystem,
and changes affect new writes. The documentation now describes changed direct
I/O behavior for Linux 7.3, while the evaluated host uses 7.2.3. Do not attribute
those newer semantics to this host or disable VM checksums solely to obtain
direct writes without measuring the actual workload.
[Btrfs compression versions](https://btrfs.readthedocs.io/en/latest/Compression.html)

### Hardware and operator choices

Keep Argon2id with cryptsetup's benchmarked passphrase cost. Arbitrarily forcing
large memory or iteration costs can make recovery slow or exhaust initrd memory.
Leave encryption-sector selection to the device topology by default. Upstream
selects 4096-byte encryption sectors for devices reporting 4096-byte physical
sectors, including 512e devices, and 512 for devices reporting only 512-byte
physical sectors. Forcing 4096 on the latter can make interrupted writes damage
a larger encrypted sector. Verify hardware and rescue compatibility before
changing this creation-time decision.
[Cryptsetup option definitions](https://github.com/mbroz/cryptsetup/blob/master/man/common_options.adoc)

Keep the workqueue defaults until end-to-end tests show a benefit. The kernel
documents synchronous workqueue bypass and warns that high-priority encryption
can reduce general system responsiveness. Weekly TRIM with Btrfs `nodiscard`
remains consistent; `discard=async` is a supported alternative, not a missing
correctness setting. Either policy requires accepting allocation-information
leakage through LUKS when discard is enabled.
[Kernel dm-crypt options](https://docs.kernel.org/admin-guide/device-mapper/dm-crypt.html),
[Btrfs discard policy](https://btrfs.readthedocs.io/en/latest/Administration.html)

I/O priority does not guarantee that maintenance stays below a particular
bandwidth. The host already sets scrub's own `--limit` to `800M`; measure
foreground latency before changing that ceiling. The Btrfs manual warns that
priority settings depend on the I/O scheduler, so `IOSchedulingClass=idle`
alone cannot establish responsiveness on every NVMe stack.
[Btrfs scrub bandwidth control](https://btrfs.readthedocs.io/en/latest/btrfs-scrub.html#bandwidth-and-io-limiting)

Retain the staged Lanzaboote integration and attended TPM-PIN enrollment. Its
current guide still marks pcrlock experimental, requires recovery credentials,
recommends a user secret for workstations and limits managed generations to
eight. PCR0 adds firmware measurements but creates another firmware-update
recovery dependency; PCR4+7 is the existing explicit choice. Neither a code
change nor a successful evaluation establishes physical enrollment, firmware
trust, kernel lockdown or a tested login boundary.
[Lanzaboote measured-boot guide](https://nix-community.github.io/lanzaboote/how-to-guides/enable-measured-boot.html)

The 2026-09-10 research used read-only source inspection, version evaluation,
feature listing and primary-source retrieval. It ran no filesystem benchmark,
disk formatting, filesystem conversion, enrollment or deployment. Latest
upstream documentation describes some behavior beyond the evaluated kernel;
those version differences are explicit above.

## Implementation validation, 2026-09-10

The review covered the current storage configuration at root revision
`7fd38c80a2aabdb16674fba7231496fa4a575bee` and the resulting working-tree
changes. The user's storage-quality request supplied the requirements;
`CONTRIBUTING.md` supplied repository conventions. The fixes retain host-local
storage policy and the reusable libvirt module's existing option boundary.

The private snapshot-directory assertion failed against the original layout.
The revised Disko VM test passes after provisioning two disposable encrypted
devices. It verifies root-only snapshot access, cache and container exclusions,
CoW inheritance for new image files, persistence over cold boots, fresh encrypted
swap, real backup and restore services, and an unavailable data volume. The
absent-volume scrub check verifies that it never starts a scrub on root.

Storage contracts, including the generated libvirt pool CoW attribute, pass.
The full encrypted Secure Boot and TPM-PIN configuration builds on the desktop
host without activation. All 25 focused backup and virtualization Python tests
pass. Formatting, spelling, local documentation links and the patch secret scan
also pass. An intermediate VM run lacked `chattr` in its test environment; adding
that fixture dependency resolved it. Concurrent test-tooling changes briefly
broke check names and unrelated helper tests; the final checks use the revised
tooling and pass.

No production drive was formatted, image converted, credential enrolled or
firmware setting changed. The VM does not run a physical TPM, libvirt workload
benchmark or disk-full retention experiment. The 20% free-space policy follows
Snapper's documented algorithm and its generated configuration is checked;
it is not a measured capacity guarantee. Provision real backup destinations,
perform offline migration and test physical boot recovery before treating the
setup as operationally complete.

## Initial research validation and limits, 2026-09-09

Read-only configuration and hardware checks established the current encryption,
boot, swap, and session-startup state. Pinned Disko and NixOS source evaluation
of the existing inactive layout succeeded using an intentionally nonexistent
by-id device. It produced eight mounts, `cryptroot`, and the existing 8 GiB
swapfile declaration. No provisioning script ran. Serializing an entire swap
option initially failed on its unset optional `label`; projecting the defined
fields succeeded. This was an evaluation-output issue, not a physical boot test.

A separate inert fixture evaluated the proposed 16 GiB randomly encrypted swap
and a LUKS volume excluded from initrd unlocking. It confirmed NixOS's generated
swap initialization unit and the absence of an early data-volume mapping. The
installed systemd 261.2 crypttab generator also produced the expected attach
unit and keyfile mount dependency using temporary output directories. No
generated service was started. These checks establish the individual mechanisms,
not a tested full two-drive installation.

No drives were formatted, TPMs enrolled, firmware settings changed, or production
configuration modified. The proposed two-drive layout has not undergone a VM
installation or a physical boot test. No filesystem benchmarks, backup restores,
YubiKey initrd tests, or suspend/resume tests ran. Upstream latest documentation
was reviewed alongside pinned source; future implementation must retain those
version distinctions. Physical TPM attack resistance was not assessed.

## Implementation gates

The revised Disko layout replaces the old swapfile with a dedicated encrypted
swap partition. Runtime configuration is gated on an offline migration setting.
Preserve a normal recovery passphrase while introducing one security layer at
a time. The rollout must pass these gates:

- Verify backups, a sample restore, target identities, and Linux-only migration
  scope. Resolve backup destination and capacity before a wipe.
- Evaluate the new layout and run an isolated Disko installation/boot test,
  including random encrypted swap and missing-data-drive behavior.
- Install offline and test passphrase recovery for both LUKS volumes.
- Establish the intended login boundary, then enable and verify signed boot.
  Audit kernel/module hardening against graphics, capture, and remote-play needs.
- Add the selected TPM-PIN or YubiKey path. Test each hardware credential,
  fallback, normal updates, older generations, and recovery after policy changes.
- Enable snapshots, backups, scrub/TRIM and alerts. Test representative workloads
  and restores before treating the migration as complete.

Use [the revised migration runbook](disko-desktop-migration.md) for the two-drive
installation. The observations and evaluation results above describe the research
phase; implementation checks and remaining physical tests are documented there
and in [storage operations](desktop-storage-operations.md).
