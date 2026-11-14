# Secure Boot and measured boot on `desktop`

Reviewed 2026-10-06 against installed Lanzaboote
`c1c5edd31802d181c8aa2c71588995d93425d650`, the updated
`c57a9234747eea6fe498d0eb601583f7ba378f06` pin, and systemd 261.3.

The desktop uses signed Lanzaboote UKIs, firmware Secure Boot, an encrypted
LUKS2 root, and TPM-PIN unlocking with an independent recovery passphrase. The
[host settings](../../hosts/nixos/desktop/local/security/secure-boot.nix) select
PCR 4 for the managed `systemd-pcrlock` policy and bind the observed PCR 7
value separately at enrollment. Automatic TPM reenrollment is disabled.

## Why the PCR 4 warning occurred

The machine remained booted into generation 20 while repeated activations
advanced the four retained boot generations to 40–43. Each generation has a
normal and USBGuard recovery UKI. Lanzaboote's
[pinned installer](https://github.com/nix-community/lanzaboote/blob/c1c5edd31802d181c8aa2c71588995d93425d650/rust/tool/systemd/src/install.rs)
selects the newest four, then garbage collects other UKIs and their PCR
measurements. It does not retain the current boot entry. The generation 20
measurement disappeared from `635-lanzaboote.pcrlock.d`.

A read-only `systemd-pcrlock predict --pcr=4` then reported that it could not
find `635-lanzaboote` in the current event log and removed PCR 4 from its
protection mask. [systemd's pcrlock implementation](https://github.com/systemd/systemd/blob/v261.3/src/pcrlock/pcrlock.c)
allows policy generation to continue with no PCRs, so a successful command exit
alone does not establish boot-chain protection. This observation does not prove
what an existing TPM token will do at the next unlock; keep the passphrase
available.

Increasing the retention limit is not a fix. With the pinned Lanzaboote source,
four generations with two UKIs each use eight PCR 4 image alternatives.
[systemd currently supports at most eight alternatives per PCR](https://github.com/systemd/systemd/issues/41526).

## Could we reserve the running generation instead?

The installed v1.2.0 installer has no option to reserve the booted generation:
it always selects the newest `configurationLimit` profile links. Removing the
USBGuard specialisation leaves one image in newly created generations, but
raising the limit to eight would only delay the same pruning problem. Seven
newest generations plus the booted one also exceeds the PCR 4 alternative
budget when a bootloader update adds a second loader measurement.

Upstream Lanzaboote has since added a
[`protectedSystem` option](https://github.com/nix-community/lanzaboote/commit/c57a9234747eea6fe498d0eb601583f7ba378f06)
that defaults to `/run/booted-system` and keeps it within the limit. Upstream
also now keeps both the old and new bootloader measurements during a
[bootloader update](https://github.com/nix-community/lanzaboote/commit/46bad145cca5d952bcd58142d4d2612e73331e49).
That doubles the possible PCR 4 paths. Its
[measured-boot guide](https://nix-community.github.io/lanzaboote/how-to-guides/enable-measured-boot.html)
therefore caps ordinary generations at four. With the USBGuard specialisation
in every generation, two bootloaders times two images times four generations
would require 16 alternatives. A later Lanzaboote update needs a smaller
generation limit or fewer specialisations before activation.

The Nix configuration removes the USBGuard recovery specialisation from new
generations while keeping USBGuard enabled. This loses the boot-menu path that
turns it off if a rule blocks a necessary input device. With one image per
generation, the useful target is four entries: the booted generation plus the
three newest when it is outside the newest four. The user must retain console
and recovery-media access if USBGuard blocks input.

Older saved generations still have the recovery specialisation. During the
transition, the host retains only two generations. Its first new normal
generation plus the old booted generation use at most three UKI alternatives;
two bootloader alternatives bring that to six PCR 4 outcomes. Raising the limit
to four before four newly created normal generations are selected could exceed
systemd's eight-outcome limit. The limit needs a later reviewed Nix change.

## Prevention in the Nix configuration

The host pins the upstream revision containing `protectedSystem`. Lanzaboote
selects the newest generations and replaces the oldest selected one with the
booted generation if necessary. Its previous/current bootloader measurements
keep PCR 4 covered through one bootloader update. Reboot before a second
bootloader update; upstream documents that remaining limitation.

The selected `boot.lanzaboote.package` includes a fail-closed
[guard](../../hosts/nixos/desktop/local/security/lanzaboote-install-guard.sh).
Before `lzbt install` changes the ESP, it compares `/run/booted-system` with
the exact generation reported by the EFI loader and requires one matching
profile link. Upstream otherwise silently skips the protection when it cannot
find a match, or may choose a different generation number when links share a
store closure. The guard cannot repair a measurement already missing from the
current boot session.

Before writing a policy, the boot-time `systemd-pcrlock-make-policy` service
requires a nonempty PCR 4 prediction. It also checks the generated JSON for
PCR 4 afterward. A missing measurement therefore leaves the existing policy
in place and reports a failed service.

This is an activation check in the NixOS configuration. It does not install an
alternate binary in a user profile or modify a boot entry outside NixOS
activation. The [Lanzaboote measured-boot guide](https://nix-community.github.io/lanzaboote/explanation/measured-boot.html)
explains the PCR 4 boot-chain measurements.

## Recovery and verification

The full desktop build, upstream protected-system VM test, and dry activation
passed. After rebooting into retained generation 43, activation of generation
44 succeeded. The managed policy retained PCR 4 with three alternatives;
both generations' UKIs and the bootloaders verified as signed. System and user
service checks showed no failed units. A subsequent reboot into generation 44
also passed: the boot was marked successful, Secure Boot remained enabled,
PCR 4 prediction retained three alternatives, and the policy service completed
both checks. Root decryption completed successfully; its logs do not identify
whether the TPM PIN or recovery passphrase performed the unlock. The retained
generation 43 still has its original USBGuard recovery image during migration.

Recover at the physical console with a tested LUKS passphrase and a bootable
recovery USB available. Confirm the target UKI is signed and its entry is on the
ESP with `sbctl verify` and `bootctl list`. Reboot into the retained entry; do not
assume the TPM PIN will unlock before testing it.

After boot, compare `bootctl status`'s current entry with the retained entries,
then check the policy service and PCR 4 prediction:

```sh
sudo systemctl status systemd-pcrlock-make-policy.service
sudo /run/current-system/systemd/lib/systemd/systemd-pcrlock predict \
  --components=/etc/pcrlock.d --components=/var/lib/pcrlock.d \
  --location=770 --pcr=4
```

The prediction must retain PCR 4 and must not report a missing
`635-lanzaboote` component. If it still excludes PCR 4, use passphrase recovery
and inspect the boot event log, component files, and policy service before
another TPM enrollment or boot update. Do not erase a working recovery slot.

## Signing keys and recovery material

The signing bundle remains root-owned outside the Nix store under
`/var/lib/sbctl`. Keep an encrypted offline backup of the bundle, ESP, and LUKS
recovery material. Losing the signing private key prevents future signed boot
updates; exposing it permits unauthorized images to be signed. Keep a tested
recovery USB and an independent LUKS passphrase for firmware or TPM changes.

## Kernel LSM and module policy

The secure-boot module preserves the NixOS-managed LSM sequence and requires
AppArmor, not a hand-built `lsm=` parameter or concurrent SELinux setup. The
previously selected `linuxPackages_latest` kernel reported both
`CONFIG_SECURITY_LOCKDOWN_LSM` and `CONFIG_MODULE_SIG` as disabled. The desktop
now selects the shared XanMod kernel; check its built configuration before
claiming lockdown or module-signature enforcement. A `lockdown=` command line
option cannot enable an LSM that was not compiled into the kernel.

The configuration does not add `lockdown=`, force kernel module signatures, or set
`security.lockKernelModules`: those choices require a separate audit of NVIDIA,
networking, and other loadable drivers. If kernel lockdown becomes a required
property, design a separate custom-kernel transition that enables the Lockdown
LSM and signs every required in-tree and out-of-tree module. Verify NVIDIA,
networking, suspend, and a rollback generation at the physical
console before enforcing module signatures.

Secure Boot protects the signed boot path. Kernel lockdown and module-signature
enforcement require separate validation on the selected kernel.
