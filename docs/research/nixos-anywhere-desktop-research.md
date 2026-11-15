# Desktop reinstall with nixos-anywhere

Reviewed: 2026-10-02. Scope: the repository's pinned nixos-anywhere
`da83557d8b0bce57a52371b888ffd6d58724e55c`, Disko
`725ea35e410ad83be4931d1bff7e090eacaf3563`, and Lanzaboote
`7c9a54a7f87b4539ddbd8bda09a8a5f5f9361aa9`. The decision is how to
prepare an attended, recoverable reinstall of the physical desktop with the
staged two-drive encrypted layout.

## Answer

Use Ethernet, physical-console access, verified backups, and an installer
configuration that binds **both** Disko devices to whole-disk by-id paths
confirmed on the target. Do not point nixos-anywhere's ordinary
`--flake ...#desktop` invocation at this layout until that binding is in place:
the checked-in Disko function defaults to deliberately nonexistent paths, and
the [pinned CLI](https://github.com/nix-community/nixos-anywhere/blob/da83557d8b0bce57a52371b888ffd6d58724e55c/docs/cli.md)
has no `--argstr` pass-through for the disk function. This is a local
configuration inference from [the Disko file](../../hosts/nixos/desktop/local/storage/disk-layout.nix)
and the CLI, not an upstream prohibition on parameterized layouts.

Treat the reinstall as attended despite nixos-anywhere's automation. The
upstream [README](https://github.com/nix-community/nixos-anywhere/blob/da83557d8b0bce57a52371b888ffd6d58724e55c/README.md)
warns that Disko overwrites the target and that the installer does not support
Wi-Fi. The existing [migration guide](../operations/disko-desktop-migration.md) requires
independent backups, restore checks, recovery media, and explicit confirmation
of both disks. It remains the authority for the destructive operation.

## Findings and sources

### Installer transport and staging

- The [pinned CLI](https://github.com/nix-community/nixos-anywhere/blob/da83557d8b0bce57a52371b888ffd6d58724e55c/docs/cli.md)
  accepts `--flake`, SSH identity and options, `--phases`, `--disko-mode`,
  `--extra-files`, `--copy-host-keys`, `--disk-encryption-keys`, and
  `--build-on`. Default phases are `kexec,disko,install,reboot`. Omitting
  `reboot` allows inspection of the mounted installation before the first boot.
  A recovery ISO can be the SSH target; kexec is then optional. If kexec is
  used, the target must meet the upstream Linux, architecture, and memory
  requirements, and its temporary installer SSH identity must be verified
  separately from the installed host identity. The pinned implementation
  starts with `StrictHostKeyChecking=no` and `UserKnownHostsFile=/dev/null`;
  its `--ssh-option` appends arguments after those defaults. OpenSSH's
  [configuration precedence](https://man.openbsd.org/ssh_config.5) uses the
  first occurrence of an option, so `--ssh-option StrictHostKeyChecking=yes`
  does **not** make this transport authenticate the installer host. Review a
  local patch or a separate verified SSH transfer before sending the host
  private key and signed artifacts. Its SSH wrapper allocates a TTY only when
  the caller has one, so an interactive Disko password prompt needs an
  attended terminal.
- [The pinned implementation](https://github.com/nix-community/nixos-anywhere/blob/da83557d8b0bce57a52371b888ffd6d58724e55c/src/nixos-anywhere.sh)
  copies `--extra-files` into `/mnt` after building the system closure and
  before `nixos-install`. Its `--copy-host-keys` copies `/etc/ssh/ssh_host_*`
  from the *installer environment* into `/mnt/etc/ssh`, skipping a destination
  already supplied by extra files. Therefore copying host keys from a fresh
  recovery ISO can preserve the ISO's temporary key, not the desktop's key.
  For this machine, use a verified, private staging tree of the original host
  key and explicitly check the installed public fingerprint before boot.
- The [pinned Disko LUKS implementation](https://github.com/nix-community/disko/blob/725ea35e410ad83be4931d1bff7e090eacaf3563/lib/types/luks.nix)
  prompts twice when no password file or key is configured. The desktop's
  [layout](../../hosts/nixos/desktop/local/storage/disk-layout.nix) takes that interactive path for
  both LUKS volumes. An unattended encrypted install therefore needs a
  deliberate credential-delivery design; a passphrase in the flake, shell
  arguments, command logs, or Nix store is unsuitable. The existing manual
  Disko procedure uses attended prompts.

### SSH identities and secrets

- The host [nix-seal declaration](../../hosts/nixos/desktop/local/nix-seal/settings.nix) reads
  the checked-in public key, while nix-seal's [NixOS module](../../nix-seal/nix/modules/shared.nix)
  defaults its decryption identity to `/etc/ssh/ssh_host_ed25519_key`.
  Reinstalling with a newly generated host key would make existing signed
  target artifacts unreadable until a separate rekey and prepare operation.
  Preserve the original Ed25519 host *private* key outside Git and the Nix
  store, restore it with root ownership and `0600` permission before first
  boot, and compare its derived public key to the checked-in identity. Follow
  the [nix-seal workflow](../secrets.md) to provision current signed ciphertext
  artifacts and check readiness before activation. Preserve the matching
  caches needed for rollback; encrypted `.age` sources alone are insufficient
  for the current signed-artifact activation path.
- SSH client authorization is separate from the server host key. The
  [desktop account policy](../../hosts/nixos/desktop/local/system.nix) already
  authorizes a MacBook public key for the normal account and a restricted root
  deployment login. A reinstall should retain the real administrator's
  *client* private key on its original device; it should not place that key
  on the desktop or in installer extra files. Verify access through the new
  wired address only after checking the installed server fingerprint against
  the backed-up key. If the server key must rotate, update trusted client
  host-key records and rekey nix-seal first as an explicit migration.
- `--extra-files` is a broad file-copy mechanism, not a secret manager. Its
  source directory and transport endpoint need private permissions and a
  deliberate inventory. The upstream CLI says copied files become root-owned
  unless `--chown` is specified, but the final modes and identities must be
  checked in `/mnt`; place no plaintext application credentials in the flake
  or repository. The desktop's [secret guide](../secrets.md) describes signed
  cache preparation and target readiness.

### Boot policy and recovery

- [Lanzaboote's preparation guide](https://github.com/nix-community/lanzaboote/blob/master/docs/getting-started/prepare-your-system.md)
  places signing keys in `/var/lib/sbctl` and requires a signed boot path
  before Secure Boot enforcement. The desktop's [rollout](../operations/secure-boot-lanzaboote.md)
  keeps Secure Boot and measured boot off for the first encrypted install,
  then tests the new boot path, enrolls firmware keys at the console, and
  finally enrolls TPM with PIN while retaining an independent recovery
  passphrase. The pinned [Lanzaboote module](https://github.com/nix-community/lanzaboote/blob/7c9a54a7f87b4539ddbd8bda09a8a5f5f9361aa9/nix/modules/lanzaboote.nix)
  enforces a bounded generation count for measured boot. Preserve the
  original signing-key bundle only in encrypted recovery storage; do not
  copy it into an installer flake or public artifact.
- Once Disko formats a target, an ordinary NixOS generation rollback cannot
  undo the partitioning or recover overwritten data. Keep the original
  system's off-machine backup, verified restore, installer checkout with
  submodules, LUKS passphrases or recovery keys, and recovery USB until the
  physical boot and restored services pass. A key for the optional data
  volume is generated on encrypted root after first boot by the local
  [enrollment helper](../../hosts/nixos/desktop/local/storage/enroll.sh); it
  should not be copied into an initrd.

## Validation and limits

This is source review, not an installation test. The local Disko defaults,
storage activation flag, SSH authorization, and nix-seal identity default were
read from the current working tree; no disk was formatted, secret copied, TPM
credential enrolled, firmware key changed, or host rebooted. The upstream
claims were checked against the pinned revisions above on 2026-10-02. The
local `ssh -G` probe with the pinned argument order reported
`stricthostkeychecking false` and `userknownhostsfile /dev/null`, confirming
that appended options do not restore host verification. The
actual target disk identities, current SSH host-key fingerprint, installer
network behavior, offline backup restore, and first-boot service behavior
remain to be verified at the physical desktop.

## Implication for this repository

The [attended install runbook](../operations/desktop-nixos-anywhere.md) now uses a private
generated flake to bind two verified by-id paths without persisting device
identifiers in public prose. The revision-guarded
`desktop-nixos-anywhere` package removes upstream's unchecked SSH defaults;
the runbook requires a console-verified installer host key. The plan keeps
`encryptedRoot.enable` enabled in the installed configuration, and prevents
the optional removable Disko layout from joining the destructive operation.
Prefer a phased run that stops before reboot for inspection. Ensure the first
boot still uses passphrase unlock and unsigned systemd-boot; enroll data-key,
Secure Boot, and TPM-PIN in the staged order in the existing migration guides.
An operator should be able to dry-run the chosen installer closure and
understand exactly which disks it can erase before approving the real command.
