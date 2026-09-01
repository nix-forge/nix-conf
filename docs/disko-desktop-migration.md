# Disko encrypted-root migration for `desktop`

`hosts/nixos/desktop/disko.nix` is the planned **offline installer** layout for
the desktop's ADATA Linux NVMe. It is not imported by the running host and it
has not been executed. Disko's `destroy,format,mount` mode repartitions and
formats the whole target disk; this is a migration, not an in-place conversion.

## Resulting layout

| Layer | Design | Purpose |
| --- | --- | --- |
| GPT / ESP | 2 GiB FAT32, mounted at `/boot`, root-only masks | UEFI, systemd-boot/Lanzaboote, signed boot generations, firmware capsules |
| Root encryption | One LUKS2 `cryptroot` container with Argon2id | Encrypts the operating system, home data, Nix store, logs, and swap at rest |
| Filesystem | One Btrfs filesystem | Checksummed COW filesystem and efficiently separated recovery domains |
| Subvolumes | `@root`, `@var`, `@log`, `@home`, `@nix`, `@snapshots`, `@swap` | Targeted snapshots/rollback without making logs, package store, or home data part of root rollback |
| Swap | 8 GiB Btrfs swapfile inside LUKS, priority `-1` | Encrypted overflow behind zram (priority `5`); hibernation remains disabled |

The layout uses the actual Linux SSD's stable model-and-serial path,
`/dev/disk/by-id/nvme-ADATA_SX8200PNP_2N1429QJEQR7`, rather than `/dev/nvme1n1`.
It leaves the Samsung Windows/games NVMe completely untouched.

## Critical Windows constraint

The currently mounted Linux ESP is also the firmware-registered **Windows Boot
Manager** location (`EFI/Microsoft/Boot/bootmgfw.efi`). Formatting the Linux
SSD as designed will therefore remove the only current Windows boot path,
despite Windows itself being on the Samsung SSD. Disko's upstream guide also
states that a whole-disk layout does not support preserving dual boot.

Do not run Disko until one of these is true:

1. You intentionally retire bare-metal Windows and have tested Windows
  recovery media plus a backup of any data you need; or
2. You independently restore/relocate Windows Boot Manager to an ESP on the
  Windows SSD and verify that it boots **with the Linux SSD disconnected**.

This migration does not attempt that Windows boot repair. It is a separate,
recovery-sensitive Windows operation.

## Staged migration

### 1. Back up first

Create verified, encrypted offline backups of home data, Nix configuration,
SSH keys, browser/profile data, MiniDV captures, and the current ESP. Btrfs
snapshots are convenient recovery points but are not backups.

### 2. Prepare recovery media

Create and test-boot a current NixOS installer USB, keeping a second device
available for these instructions. Export the present ESP and NVRAM entries:

```sh
sudo install -d -m 700 /root/boot-recovery
sudo tar --xattrs --acls -C /boot -cpf /root/boot-recovery/esp-before-disko.tar .
sudo efibootmgr -v | sudo tee /root/boot-recovery/efibootmgr-before-disko.txt
```

### 3. Resolve Windows boot and identify the target

Resolve the Windows constraint above and verify the target from the installer
before destroying anything:

```sh
readlink -f /dev/disk/by-id/nvme-ADATA_SX8200PNP_2N1429QJEQR7
lsblk -o NAME,PATH,SERIAL,SIZE,FSTYPE,MOUNTPOINTS
```

The path must resolve to the 953.9 GiB ADATA drive, not the 1.8 TiB Samsung
Windows/games drive and not the installer USB.

### 4. Run Disko from the installer

Use this repository revision, including the already pinned Disko input, and
run the destructive operation only after the checks above pass:

```sh
sudo nix run github:nix-community/disko/ff8702b4de27f72b4c78573dfb89ec74e36abdf1 \
  -- --mode destroy,format,mount hosts/nixos/desktop/disko.nix
```

Disko will request a new LUKS passphrase interactively. Use a long unique
passphrase; do not put it in Nix, Git, `/tmp`, or a shell history.

### 5. Install the Disko system configuration

Add `./disko-system.nix` to the desktop's `modules` list **only in the
installer copy of `hosts/nixos/desktop/default.nix`**, then install. For
example, append it beside the other explicit host paths:

```nix
modules = with modules; [
  # existing module list …
  ./disko-system.nix
];
```

It imports the pinned Disko NixOS module and disables the legacy plaintext
root/swap declarations. Do not add it to the live configuration before
formatting. Keep it in the installed configuration after migration.

### 6. Prove passphrase and recovery-key boot

Boot with the LUKS passphrase twice and test an older generation before
introducing TPM unlock. Create and store a recovery key offline:

```sh
sudo systemd-cryptenroll --recovery-key /dev/disk/by-partlabel/NIXOS-CRYPTROOT
sudo systemd-cryptenroll /dev/disk/by-partlabel/NIXOS-CRYPTROOT
```

Keep both a tested passphrase and the recovery key. The TPM is convenience plus
boot-state binding; it is not the only recovery mechanism.

### 7. Roll out Secure Boot at a physical console

Follow [the Secure Boot rollout](secure-boot-lanzaboote.md) at a physical
console. First prove Lanzaboote boots with firmware Secure Boot disabled, then
enroll keys while retaining Microsoft certificates, and finally enable firmware
enforcement.

### 8. Enroll TPM unlock last

Only after steps 1–7 are proven, enable
`security.secureBootLanzaboote.measuredBoot`, import
`hosts/nixos/desktop/disko-tpm-unlock.nix`, rebuild, reboot once, then enroll
the policy with a TPM PIN:

```sh
sudo systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-with-pin=true \
  --tpm2-pcrlock=/var/lib/systemd/pcrlock.json \
  /dev/disk/by-partlabel/NIXOS-CRYPTROOT
```

The TPM/PIN path is tested against Lanzaboote's policy rather than a brittle
fixed PCR measurement. Test a normal TPM/PIN boot and the recovery-key boot
before treating the migration as complete.

## Design boundaries

- The ESP is intentionally unencrypted: UEFI must read it before Linux starts.
  Secure Boot authenticates its boot artifacts; it does not conceal their
  metadata.
- LUKS discard is enabled because this NVMe supports it and the desktop already
  uses periodic trim. The tradeoff is visibility of which encrypted sectors are
  unused, not plaintext disclosure. Set `allowDiscards = false` in `disko.nix`
  before installation if allocation-pattern confidentiality is the higher
  priority.
- Disko provides the layout, not a backup service or an automatic snapshot
  policy. Configure and test an encrypted off-host backup target before relying
  on snapshots for recovery.
- Do not enable automatic TPM re-enrollment. The existing Lanzaboote module
  intentionally keeps it off; policy changes and recovery paths need attended
  verification on this desktop.
