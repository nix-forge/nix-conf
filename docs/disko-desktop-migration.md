# Desktop encrypted-storage migration

The two-drive layout is implemented but staged. The live configuration keeps
`hardware.storage.encryptedRoot.enable = false`. Changing that setting does not
encrypt existing data. Disko's `destroy,format,mount` operation erases both
selected drives, including native Windows and its boot files.

Read [the design research](desktop-storage-research.md) for the filesystem and
boot-policy tradeoffs, and [storage operations](desktop-storage-operations.md)
for snapshots, backups and recovery checks.

## Installed layout

| Device | Contents |
| --- | --- |
| System SSD | 2 GiB FAT32 ESP; 16 GiB randomly encrypted swap; remaining space LUKS2 `cryptroot` containing Btrfs |
| Data SSD | LUKS2 `cryptdata` containing a separate Btrfs filesystem |
| System subvolumes | Root, home, Nix store, `/var`, logs, caches, Docker, containerd and rootless Docker |
| Data subvolumes | `/srv/data`, `/srv/data/work`, `/mnt/games`, `/var/lib/libvirt/images` |

Both Btrfs filesystems use data SINGLE, metadata DUP and `compress=zstd:1`.
They do not form a pool or RAID. Periodic trim passes through LUKS; continuous
Btrfs discard is disabled. This reveals allocation patterns to an observer of
the encrypted device. Swap gets a new encryption key each boot and cannot be
used for hibernation. Existing zram remains the higher-priority swap tier.

Normal operation uses one root unlock. A private key on encrypted root unlocks
the optional data SSD. A missing data SSD must leave login available and must
prevent applications from writing replacement data beneath its mount points.
The normal greeter requires authentication; Sunshine becomes available after
interactive login.

## Before erasing either drive

1. Provision independent encrypted backup storage outside both selected SSDs.
   Back up home, configuration and submodules, SSH identities, application data,
   existing games/saves and any Windows files still needed. Stop databases,
   containers and VMs before their final export or cold copy.
2. Restore representative files and actual important application data into a
   separate directory. Check contents and permissions. Retain the backup's
   password and recovery instructions independently of this desktop.
3. Save the current ESP, UEFI boot entries, sealed-secret runtime cache and the
   private identity required to decrypt that cache. Follow [secrets.md](secrets.md).
   Do not put plaintext secrets in the repository or Nix store.
4. Test a NixOS recovery USB in UEFI mode. Confirm networking, both target SSDs,
   keyboard and recovery commands work. Keep these instructions on another device.
5. Keep a complete installer copy of this checkout, including submodules and
   uncommitted implementation files, outside the drives being erased and outside `/mnt`. Disko mounts the new root
   at `/mnt`, hiding anything previously beneath that directory. A normal
   Git clone does not contain uncommitted files. Verify the copy before proceeding.

An empty backup configuration is deliberately not a completed backup strategy.
Do not format while the only copies of any required data remain on these SSDs.

## Partition and install from recovery media

From the installer, identify both whole drives by their stable by-id paths.
Do not use an NVMe index or a partition path. Confirm model, size, serial and
contents locally; keep captured identifiers private.

```sh
lsblk -o NAME,PATH,TYPE,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS
read -r -p 'System SSD whole-disk by-id path: ' system_disk
read -r -p 'Data SSD whole-disk by-id path: ' data_disk
readlink -f -- "$system_disk"
readlink -f -- "$data_disk"
```

The two paths must resolve to different whole devices. Neither device nor its
children may be mounted, used as swap, or held by a device-mapper mapping.
Double-check that the installer, checkout and backups are elsewhere. `/mnt`
and its descendants must be unmounted, and `/mnt` must be an empty ordinary
directory or absent, so installation cannot hide required files or mounts.

The following command is destructive. Run it only after the checks above and
an explicit confirmation of both targets:

```sh
sudo nix run github:nix-community/disko/ff8702b4de27f72b4c78573dfb89ec74e36abdf1 \
  -- --argstr systemDisk "$system_disk" --argstr dataDisk "$data_disk" \
  --mode destroy,format,mount hosts/nixos/desktop/disko.nix
```

Disko requests LUKS passphrases interactively. Give each container a strong
recovery passphrase and record it securely offline. Do not capture it in shell
variables, command arguments or files under the checkout.

In the installer copy, change
`hosts/nixos/desktop/local/storage-deployment.nix` to:

```nix
{ lib, ... }: {
  hardware.storage.encryptedRoot = {
    enable = lib.mkDefault true;
    unlockMethod = lib.mkDefault "passphrase";
  };
}
```

Keep Secure Boot and measured boot disabled for the first installation. The
Disko module is already imported by the host. It derives installed mounts from
partition labels and mapper names; private by-id arguments are only required
for the destructive installer operation. Its default `UNCONFIGURED-*` paths
intentionally cannot select a real disk.

Restore the needed data and secret identities into the new mounted tree. Keep
new filesystem boundaries intact. Do not overwrite generated `/etc/fstab`,
`/etc/crypttab`, or the new ESP with old versions. Preserve ownership, ACLs,
extended attributes and sparse VM files when copying application state.

Install using the prepared checkout:

```sh
sudo nixos-install --flake "path:$PWD#desktop"
```

This intentionally includes the private installer's uncommitted enable setting.
Ensure the installed configuration copy retains that setting for future rebuilds.

## First boot and data unlock

Boot with the root passphrase. The data drive may remain unavailable until its
private automatic-unlock key is enrolled; this must not prevent login. At the
installed physical console:

```sh
sudo desktop-storage-enroll data-key
sudo systemctl restart systemd-cryptsetup@cryptdata.service
sudo systemctl start desktop-data-ready.service
for path in /srv/data /srv/data/work /mnt/games /var/lib/libvirt/images; do
  findmnt --mountpoint "$path"
done
```

`data-key` creates a private random key only if absent, adds it to the data
container using its existing passphrase, and tests the key. It keeps the
passphrase slot. Re-running it never overwrites a candidate key.

Test both recovery passphrases independently. Add recovery keys if desired,
record them offline, and test them before relying on them:

```sh
sudo cryptsetup open --test-passphrase /dev/disk/by-partlabel/NIXOS-CRYPTROOT
sudo cryptsetup open --test-passphrase /dev/disk/by-partlabel/NIXOS-CRYPTDATA
sudo systemd-cryptenroll --recovery-key /dev/disk/by-partlabel/NIXOS-CRYPTROOT
sudo systemd-cryptenroll --recovery-key /dev/disk/by-partlabel/NIXOS-CRYPTDATA
sudo desktop-storage-enroll headers
```

Move the resulting header backups to independent encrypted recovery storage.
Repeat after credential changes. Header backups contain sensitive keyslot
material; an old backup can restore a credential that was subsequently revoked.

Reboot twice and verify data mounts, login, NVIDIA and normal workloads.
Test a rollback generation. Suspend remains disabled by the existing desktop
compatibility policy; enabling and testing it is a separate change. Then follow the
[Secure Boot rollout](secure-boot-lanzaboote.md).

## Select hardware unlock last

After Secure Boot enforcement and managed measured boot have each passed a
physical boot test, enroll TPM plus PIN:

```sh
sudo desktop-storage-enroll tpm-pin
```

The command checks firmware enforcement and the managed PCR policy, tests a
recovery passphrase, and refuses to overwrite an existing TPM enrollment.
Change `unlockMethod` to `"tpm-pin"`, build a boot generation, and test both PIN
and recovery-passphrase boot. Normal PIN attempts are subject to the TPM's
lockout policy; do not repeatedly guess.

Optional YubiKey boot enrollment is separate from web-account credentials:

```sh
sudo desktop-storage-enroll fido2
```

Connect one key at a time and repeat for the second. This requests PIN and touch.
Select `unlockMethod = "fido2"` only after enrollment. Keep an independent
recovery passphrase. Never reset FIDO2 as a troubleshooting shortcut: that also
invalidates the key's existing FIDO credentials for online accounts.

TPM-PIN is the intended everyday path; the YubiKeys are optional. Automatic
TPM token replacement is intentionally disabled. Test normal boot, recovery
boot and a signed rollback before treating the migration as complete.

## Validation and remaining hardware tests

Run `just desktop-storage-check` for the configuration contracts, disposable
Restic recovery tests and the two-disk Disko VM installation test. Run
`just desktop-storage-build` on `desktop` to build the proposed encrypted,
Secure Boot and TPM-PIN configuration without activation or changing deployment
flags. This build is separate from enrolling firmware or disk credentials.

The VM check provisions two LUKS2/Btrfs devices, verifies metadata DUP and
randomly encrypted swap across cold boots, checks data persistence and snapshot
exclusions, and exercises the generated backup and verification services.
It also boots with the data unlock key unavailable and verifies home snapshots
and cleanup remain functional. Missing backup media must fail without creating
a replacement repository beneath an unmounted directory. The cold-backup guard
must refuse normal multi-user operation.

VM fixture passphrases are disposable and its partitions and Argon2 parameters
are reduced for testing. The test uses the pinned standard VM kernel, not the
physical desktop's kernel and drivers. It does not test physical TPM enrollment,
YubiKey initrd access, firmware policy, a physically disconnected SSD, actual
backup hardware, or restored production applications. Those remain attended
migration acceptance tests.
