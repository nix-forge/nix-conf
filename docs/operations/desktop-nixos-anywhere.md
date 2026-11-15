# Attended desktop reinstall with nixos-anywhere

This procedure uses the [pinned-tool research](../research/nixos-anywhere-desktop-research.md)
and the [storage migration checklist](disko-desktop-migration.md). It is a
preparation and execution runbook, not authorization to erase a drive. The
two-drive layout destroys **both entire selected drives**. Confirm what will
replace any Windows installation before selecting a data drive.

## Prepare while the current desktop is still running

1. Decide what the wipe must preserve. For data to retain, complete the
   independent backup and restore checks in the migration guide. Include the
   full Git checkout with submodules and working-tree changes, home data,
   application state, and any Windows files to retain. Put the installer
   checkout and backup outside both selected drives. If intentionally
   discarding those files, record that decision and still preserve the SSH and
   nix-seal identities needed for continuity. Test recovery media and keep the
   disk passphrases off the desktop.
   The installed desktop has one local Restic destination on the separately
   provisioned encrypted USB HDD. Keep that HDD outside the two internal Disko
   targets, and verify
   a Restic snapshot, repository read, and representative restore when retaining
   source data. An interrupted backup with no snapshot is not a recovery point.
   The MacBook may hold the installer closure
   and the small recovery credentials needed to unlock the HDD; the desktop
   data backup stays on the HDD. Media stored on that same HDD needs another
   copy if it cannot be reacquired.
2. Save all `/etc/ssh/ssh_host_*` files, especially the Ed25519 private key
   and its public file, the host
   `/var/lib/nix-seal/cache/v1`, the desktop user's
   `~/.ssh/id_ed25519` and `~/.cache/nix-seal/v1`, and any Secure Boot signing
   keys in private encrypted backup storage. These are separate host and user
   identities. Compare the public keys derived with `ssh-keygen -y` against
   their checked-in `identity.pub` files. Do not put private keys in Git, a
   flake, Nix store, command arguments, or logs. Keep the MacBook's client
   private key on the MacBook; its *public* key is already authorized for the
   installed desktop. Retain previous signed artifacts for rollback. If
   retaining Actual data, capture its vault image in the attended cold backup
   and verify its separate recovery key; a TPM enrollment alone is not a
   reliable restore credential after reinstalling the host.
3. Make a complete external checkout for the installation. The installer
   generator forces passphrase unlock for the first boot; keep the desktop's
   lasting TPM-PIN setting in `hosts/nixos/desktop/local/storage/deployment.nix`.
   Ensure the checkout contains the layout, all submodules, and current
   encrypted secret sources.
   Prepare and authenticate signed nix-seal artifacts for this exact external
   checkout using [the secret workflow](../secrets.md); copy the matching host
   and home caches into encrypted recovery storage. A cache from an older
   policy or changed ciphertext is not enough for first activation.
4. Identify the two intended whole drives with `lsblk` and
   `/dev/disk/by-id/`. Reject partition links, an attached backup drive, and
   any disk still containing data to keep. Compare models, sizes, and
   partitions at the physical console. The two links must resolve to distinct
   whole disks.
5. Generate a private installer flake on storage that will survive formatting:

   ```sh
   python3 hosts/nixos/desktop/local/storage/scripts/prepare_desktop_installer.py \
     --source "$external_checkout" \
     --output "$external_checkout_parent/desktop-installer" \
     --system-disk "$system_disk" --data-disk "$data_disk"
   chmod 700 "$external_checkout_parent/desktop-installer"
   ```

   The generator rejects duplicate and partition by-id names. It does not
   certify that the selected hardware is safe to erase. Review its private
   `flake.nix`, then evaluate both disk attributes and the enabled root layout.
   `nix eval` is harmless; the Disko *script must never be executed* during
   preparation.

   ```sh
   plan="path:$external_checkout_parent/desktop-installer"
   workstation-task nix eval --raw "$plan#nixosConfigurations.desktop.config.disko.devices.disk.system.device"
   workstation-task nix eval --raw "$plan#nixosConfigurations.desktop.config.disko.devices.disk.data.device"
   workstation-task nix eval --json "$plan#nixosConfigurations.desktop.config.hardware.storage.encryptedRoot.enable"
   ```

6. Build the installation system, Disko script, and Restic recovery tool **on
   the running desktop** through `workstation-task`, then save their store
   closures outside the target
   drives. The installer configuration forces passphrase unlock and leaves
   Secure Boot, measured boot, and the optional removable HDD layout disabled.

   ```sh
   disko_script=$(workstation-task nix build --no-link --print-out-paths \
     "$plan#nixosConfigurations.desktop.config.system.build.diskoScript")
   system=$(workstation-task nix build --no-link --print-out-paths \
     "$plan#nixosConfigurations.desktop.config.system.build.toplevel")
   restic=$(workstation-task nix build --no-link --print-out-paths \
     "$plan#nixosConfigurations.desktop.pkgs.restic")
   nix path-info -S "$disko_script" "$system" "$restic"
   ```

   Confirm that the remote store or external medium has room for the reported
   closures **before** wiping `/nix`. If using the MacBook Nix store, copy the
   three paths with
   `nix copy --to ssh-ng://macbook --no-check-sigs "$disko_script" "$system" "$restic"`
   and verify them with `nix path-info --store ssh-ng://macbook "$disko_script"
   "$system" "$restic"`. Record the resulting store paths in a private note on
   the MacBook and set `disko_script`, `system`, and `restic` there before the
   commands below. `--no-check-sigs` is needed when copying locally built,
   unsigned paths over the authenticated SSH connection. The MacBook needs a
   matching checkout to run the installer; retain that checkout and transfer
   it back to the new desktop for future local rebuilds. Do
   not proceed when the only copies of the closures are on a target drive.

## Boot the NixOS installer and verify transport

Use a NixOS recovery USB at the physical desktop console, connected by
Ethernet. The pinned nixos-anywhere installer does not support Wi-Fi. Boot in
UEFI mode; enable `sshd` in the installer and put the MacBook public key in
`/root/.ssh/authorized_keys` with mode `0600`. Keep its private key on the
MacBook. Read the installer's Ed25519 SSH host-key fingerprint at the physical
console. On the MacBook, capture the installer's public key in a private
`known_hosts` file, then compare its fingerprint with the console value before
sending any private data or running Disko. This is a **temporary installer**
host key; it is distinct from the backed-up installed desktop key.

```sh
# On the installer console:
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
# On the MacBook, with installer_host set to the wired address:
umask 077
ssh-keyscan -t ed25519 "$installer_host" > "$installer_known_hosts"
ssh-keygen -lf "$installer_known_hosts"
```

Compare the full key fingerprint shown by both commands at the console. The
scan alone does not authenticate the key.

Use `.#desktop-nixos-anywhere` from this repository on the MacBook. That pinned
package removes upstream's hard-coded `StrictHostKeyChecking=no` and
`UserKnownHostsFile=/dev/null`; the two explicit options below then take
effect. Do not substitute the unpatched upstream executable.

```sh
installer_bin=$(nix build --no-link --print-out-paths \
  "path:$external_checkout#desktop-nixos-anywhere")/bin/nixos-anywhere
ssh_args=(--ssh-option "UserKnownHostsFile=$installer_known_hosts" \
  --ssh-option StrictHostKeyChecking=yes)
ssh -o "UserKnownHostsFile=$installer_known_hosts" \
  -o StrictHostKeyChecking=yes root@"$installer_host" \
  'lsblk -o NAME,TYPE,SIZE,MODEL,FSTYPE,MOUNTPOINTS; findmnt /mnt || true'
```

Use an interactive terminal for the Disko phase. On the MacBook, confirm
`nix path-info "$disko_script" "$system"` succeeds before starting.

Check the two by-id links again **inside the installer**. `readlink -f`
must resolve to two different whole drives; `lsblk -dn -o TYPE` must say
`disk` for each. Inspect every child partition and any existing Windows
content. Neither target nor a child may be mounted or used by swap or an open
mapper. Verify the checkout, closures, and backups are off both targets. Keep
physical console access for both LUKS passphrase prompts.

## Format, restore identities, install

After an explicit review of the two physical targets, run the destructive
Disko phase from the MacBook terminal. `--store-paths` uses the prebuilt
desktop closures; it does not depend on the installer's ability to build this
large configuration. The command omits kexec because the NixOS recovery USB
is already running, and omits reboot for inspection.

```sh
"$installer_bin" --target-host root@"$installer_host" \
  "${ssh_args[@]}" --store-paths "$disko_script" "$system" \
  --phases disko
```

Once Disko has mounted the new root at `/mnt`, recover from the encrypted USB
HDD without placing desktop data on the MacBook. Keep the HDD outside `/mnt`;
mount its `@homelab` subvolume read-only at a separate path under `/run`. If
restoring a Restic snapshot, bring the prebuilt Linux Restic closure into the
installer over the **verified** SSH connection. From the MacBook, this
transfers the closure without building on the recovery USB:

```sh
nix-store --export $(nix-store --query --requisites "$restic") |
  ssh -o "UserKnownHostsFile=$installer_known_hosts" \
    -o StrictHostKeyChecking=yes root@"$installer_host" nix-store --import
```

Reveal the sealed HDD recovery key with nix-seal and the administrator identity
on the MacBook. If using Restic, reveal its separate sealed password. Stream
each value separately over the
verified SSH connection into root-only files on the installer's `/run` tmpfs;
never put their contents in a shell argument or the Nix store. Keep the
administrator identity on the MacBook. The newly chosen root LUKS passphrase
must also remain available before nix-seal activation, so enter it at the
physical console and retain an independent recovery copy.
Unlock `/dev/disk/by-partlabel/HOMELAB-CRYPT` with the key file, mount
`/dev/mapper/homelab` using `-o ro,subvol=@homelab` at `/run/desktop-backup`.
Inspect the previously verified Restic snapshot ID if one exists. For a
separately verified identity archive, review its member list and compare its
SHA-256 value before extracting only the intended SSH keys and nix-seal caches:

```sh
identity_archive=/run/desktop-backup/backups/<reviewed-identity-directory>/identities.tar
tar -tf "$identity_archive"
expected=$(cut -d ' ' -f 1 "$identity_archive.sha256")
actual=$(sha256sum "$identity_archive" | cut -d ' ' -f 1)
test "$expected" = "$actual"
tar --acls --xattrs --numeric-owner -C /mnt -xpf "$identity_archive"
```

Restore the host SSH keys, home SSH key, and both signed nix-seal caches from
the checked snapshot or a separately verified encrypted-HDD identity archive
before installation. An identity archive contains no home documents or
application state. Create the per-user `.cache` and rootless Docker Btrfs
subvolumes before restoring home data, as described in the migration guide.
When retaining application data, restore it from checked final and cold
snapshots with services stopped. Set the installed host key to root `0600` and
the user key to its intended account `0600`; compare their derived public keys
with the checked-in identities. Do not use `--copy-host-keys`, which copies the
temporary recovery USB key. Check `nix-seal` readiness against the install
system plan. Do not overwrite the new `fstab`, `crypttab`, or ESP with files
from the old system.

Run the install phase only after those checks:

```sh
"$installer_bin" --target-host root@"$installer_host" \
  "${ssh_args[@]}" --store-paths "$disko_script" "$system" \
  --phases install
```

Inspect `/mnt/etc/ssh`, `/mnt/home`, the generated boot files, and the
installed root's permissions. Confirm `/mnt/etc/ssh/ssh_host_ed25519_key`
still derives the checked-in public key. Then unmount cleanly and reboot from
the physical console. On first boot, enter the root LUKS passphrase; verify
login and SSH at the wired address only after checking the restored server
fingerprint. Enroll the data-drive key and test backups, recovery passphrases,
normal services, and two reboots as documented in the migration guide.

After a future reinstall, keep the installed encrypted layout as the source
for desktop builds. Re-enable Secure Boot and TPM plus PIN only after the
passphrase-based installation and recovery boot both work. Never erase the
independent backup as part of this run.
