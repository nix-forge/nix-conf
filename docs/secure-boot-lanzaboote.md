# Secure Boot and TPM rollout for `desktop`

Design review, 2026-09-09: [the storage and boot research](desktop-storage-research.md)
compares automatic TPM, TPM-PIN, and FIDO2 unlocking. The staged implementation
uses a normal greeter and recommends TPM-PIN after the signed boot path has
been tested. See [the migration guide](disko-desktop-migration.md).

This desktop is intentionally **not enabled** for Lanzaboote yet. Firmware
Secure Boot is currently disabled, and its root filesystem is Btrfs without
LUKS2 encryption. The configuration stages the tooling and retains the normal
systemd-boot path until an attended rollout is complete.

Do not enable this remotely. Use the physical console, keep a second device
available for the documentation, and test each reboot before proceeding.

## Preconditions

- Create and successfully boot a current NixOS installer/recovery USB. Keep
  the LUKS recovery material with it once disk encryption is introduced.

- Back up the ESP and the current UEFI boot order to encrypted offline
  storage. Do not copy Secure Boot private keys to the Nix store or git.

  ```sh
  sudo install -d -m 700 /root/boot-recovery
  sudo tar --xattrs --acls -C /boot -cpf /root/boot-recovery/esp-before-lanzaboote.tar .
  sudo efibootmgr -v | sudo tee /root/boot-recovery/efibootmgr-before-lanzaboote.txt
  ```

- Confirm UEFI mode, TPM availability, and the future measured-boot support
  before changing any firmware keys:

  ```sh
  bootctl status
  test -d /sys/firmware/efi
  /run/current-system/systemd/lib/systemd/systemd-pcrlock is-supported
  grep -E 'CONFIG_SECURITY_LOCKDOWN_LSM|CONFIG_MODULE_SIG' /boot/config-"$(uname -r)"
  ```

  The currently deployed desktop satisfies the UEFI, TPM2, and pcrlock
  preflight. Its root is unencrypted, so do not enroll TPM2 disk unlocking.

- Set a strong firmware administrator password and retain a documented,
  physical recovery procedure. Secure Boot is ineffective against someone who
  can alter firmware policy or boot an untrusted external device.

## Staged Secure Boot activation

- With firmware Secure Boot still disabled, create the root-owned key bundle:

  ```sh
  sudo sbctl create-keys
  sudo sbctl status
  ```

  Back up `/var/lib/sbctl` to encrypted offline storage. Loss of its private
  key prevents signing future NixOS boot artifacts; disclosure permits an
  attacker to sign them.

- Change only `security.secureBootLanzaboote.enable` to `true` in
  `hosts/nixos/desktop/local/security-secure-boot.nix`, then build the boot
  generation locally:

  ```sh
  sudo nixos-rebuild boot --flake .#desktop
  sudo sbctl verify
  ```

  `sbctl verify` must show the systemd bootloader and each
  `EFI/Linux/nixos-generation-*.efi` image as signed. It is expected for
  separate legacy `EFI/nixos/kernel-*` files to be unsigned: Lanzaboote boots
  the signed generation images instead.

- Reboot once with firmware Secure Boot still disabled. Confirm that the new
  Lanzaboote generation starts normally, NVIDIA/desktop functionality works,
  and `bootctl status` continues to show TPM2 support. This verifies the
  replacement loader before firmware enforcement is enabled.

- Enter the MSI firmware setup. Keep UEFI mode enabled. Follow the firmware's
  Secure Boot key-management flow to enter Setup Mode without clearing the
  revocation database (`dbx`). The exact menu labels vary by firmware release;
  do not use a destructive “clear all Secure Boot settings” action.

- Boot the already-tested NixOS generation and enroll the local keys while
  retaining Microsoft certificates for signed option ROM and recovery-media
  compatibility:

  ```sh
  sudo sbctl enroll-keys --microsoft
  sudo sbctl status
  ```

  Then enable firmware Secure Boot enforcement and reboot. Verify:

  ```sh
  bootctl status
  sudo sbctl verify
  ```

  `bootctl status` should report Secure Boot enabled in user mode. Keep the
  tested recovery USB and ESP backup until several normal updates and rollbacks
  have succeeded.

## TPM and measured boot

Lanzaboote Measured Boot is not the same as Secure Boot. It uses TPM PCR
measurements to release a secret only to an expected boot state. It becomes
meaningful for this desktop after a LUKS2 full-disk-encryption migration.

After the encrypted layout has passed recovery tests, enable `measuredBoot`
in `hosts/nixos/desktop/local/security-secure-boot.nix`. The shared module uses
PCR 4 for the measured boot chain and PCR 7 for Secure Boot policy. Build a boot
generation and reboot with the passphrase before enrolling a TPM credential.

At the physical console, use the installed helper:

```sh
sudo desktop-storage-enroll tpm-pin
```

It verifies Secure Boot enforcement, the managed PCR policy and the recovery
passphrase before adding a TPM slot with a PIN. It refuses to replace an existing
TPM token. Then set `hardware.storage.encryptedRoot.unlockMethod = "tpm-pin"`
in the host-local deployment settings and build another boot generation.
Test PIN unlock, passphrase recovery and a signed rollback generation.

Lanzaboote manages the measured policy. Automatic TPM token replacement remains
disabled. Firmware policy changes can invalidate enrollment, so retain an
independent recovery credential and perform any necessary re-enrollment at the
console after checking the new boot state.

## Kernel LSM and module policy

The secure-boot module preserves the NixOS-managed LSM sequence and requires
AppArmor, not a hand-built `lsm=` parameter or concurrent SELinux setup. The
currently selected `linuxPackages_latest` kernel reports both
`CONFIG_SECURITY_LOCKDOWN_LSM` and `CONFIG_MODULE_SIG` as disabled. Therefore,
on this desktop Secure Boot authenticates the UEFI boot chain but does **not**
provide kernel lockdown or module-signature enforcement. A `lockdown=` command
line option cannot enable an LSM that was not compiled into the kernel.

We deliberately do not add `lockdown=`, force kernel module signatures, or set
`security.lockKernelModules`: those choices would affect the staged
non-Secure-Boot system and require a separate audit of NVIDIA, FireWire capture,
networking, and other loadable drivers. If kernel lockdown becomes a required
property, design a separate custom-kernel transition that enables the Lockdown
LSM and signs every required in-tree and out-of-tree module. Verify NVIDIA,
capture, suspend, networking, and a rollback generation at the physical
console before enforcing module signatures.

This separation preserves Secure Boot's offline boot-chain integrity benefit
without turning a normal driver update into a boot-recovery event or claiming a
runtime kernel-integrity boundary that the selected kernel does not provide.
