# Desktop VM setup review

Reviewed: 2026-09-10. Scope: the NixOS desktop's libvirt host and declared Windows
runtime. Review base: `7fd38c80a2aabdb16674fba7231496fa4a575bee`, including existing
working-tree changes. Requirements came from the request to verify this
computer's VM setup and research declarative and automated improvements.
Upstream sources below were consulted on the review date.

## Answer

Keep libvirt/QEMU/KVM and finish the existing Windows lifecycle. The host has
working virtualization support, active networks and storage, and a declared
Windows domain. Windows itself is not installed. Its disk and installation ISO
are absent, and the privileged installation helper reports `uninstalled`.

Five defects were fixed in the working tree: the sudo executable used by both
CLIs, premature pipeline termination, autostart parsing, IOMMU detection, and
deferred domain reconciliation. These fixes passed focused checks but have not
been activated. Existing uncommitted storage and test changes were preserved.

## Observed state

| Component | Evidence | Result |
| --- | --- | --- |
| Host acceleration | `virt-host-validate qemu` | Hardware virtualization, KVM and IOMMU checks pass |
| Services | systemd state | libvirtd, both setup services, libvirt-guests and nftables active |
| VM inventory | Read-only system libvirt connection | One declared Windows domain, shut off; no QEMU guest process observed |
| Networks | `net-list`, network XML | Management and NAT networks active, persistent and autostarted; fixed guest leases declared |
| Storage | `pool-list`, pool XML, privileged doctor | Default pool active at the configured image directory; Btrfs NOCOW inheritance present |
| Guest hardware | Inactive domain XML | 4 vCPUs, 8 GiB RAM, VirtIO SCSI, Secure Boot firmware and TPM 2.0 declared |
| Installation | Privileged `plan` and `phase` | Disk and ISO missing; no installation marker |
| SSH client | Effective SSH configuration | Pinned alias, key-only batch login and strict host-key checking configured |
| Recovery | Host configuration evaluation and timers | No backup destinations or Restic jobs; encrypted storage profile disabled |

Network bridges reported link-down routes while no guest was attached. That
does not mean the libvirt networks are inactive. DHCP delivery, NAT traffic,
guest-to-host isolation, Windows boot, SSH login, actual Secure Boot enforcement
and guest-agent operation remain untested until a guest is installed.

The installed system's version label ends in `0968519`; the reviewed
configuration's label ends in `c043004`. Installed libvirt is
12.7.0 and QEMU is 11.1.0. This distinction matters when comparing generated
helpers with the installed sudo allowlist.

## Defects and fixes

### Management commands bypassed the privileged sudo wrapper

Both `vm` and `windows-vm` substituted `pkgs.sudo` directly. The installed `vm list`
failed because the Nix store binary has no setuid bit. The NixOS security module
installs privileged wrappers separately. Both entry points now use
`config.security.wrapperDir + "/sudo"`, preserving the fixed command allowlist.
The configuration contract checks both generated entry points.
See [NixOS wrapper implementation](https://github.com/NixOS/nixpkgs/blob/c043004/nixos/modules/security/wrappers/default.nix).

The new helpers and their sudo rules must be activated together. Running a newly
built CLI against the old system can produce a password-required error because
its new immutable helper path is not in the installed allowlist.

### Healthy libvirt objects could fail pipeline checks

Under `pipefail`, `virsh ... | grep -q ...` can fail when grep finds its match,
exits, and virsh receives SIGPIPE while printing later fields. A live read-only
network query reproduced pipeline statuses `141 0`. The installed doctor falsely
reported both networks and the storage pool inactive. The same pattern in setup
could attempt to start an already active object and fail reconciliation.

The affected status pipelines now consume the complete output with ordinary
grep redirected to `/dev/null`. Disk-identity parsers also consume later device
rows instead of exiting early. Fixtures that write status fields and device rows
separately failed before the changes and pass afterward. The listening-port
check uses the same correction.

### Doctor misread autostart and IOMMU state

Libvirt 12.7 prints both `Autostart` and `Autostart Once`. The prefix match
collected both values and reported a false mismatch. The parser now matches the
exact persistent-autostart field. These are independent libvirt settings, as
documented in the [domain API](https://libvirt.org/html/libvirt-libvirt-domain.html).

The generated noninteractive Bash lacks `compgen`. Doctor therefore warned that
IOMMU groups were absent even though host validation found them. Ordinary Bash
pathname expansion now detects the groups without completion support.

### Running guests never received deferred persistent hardware updates

The reconciler previously skipped a running guest entirely. Stopping and starting
the guest did not rerun reconciliation, so a rebuild's changed XML could remain
unapplied. The service now stages persistent XML with `define --validate`, while
retaining UUID/disk ownership checks and the installation-marker exception.
It reports that hardware changes require shutdown and start.

Libvirt supports updating a running guest's persistent definition without
altering its live process. See [virsh define](https://libvirt.org/manpages/virsh.html#define).
No synchronous libvirt calls were added to hooks, which would risk a
[documented deadlock](https://libvirt.org/hooks.html#calling-libvirt-functions-from-within-a-hook-script).

## Improvements in priority order

1. Activate the reviewed host changes, then complete the existing installer.
   Supply the declared Microsoft ISO, authorize the generated public key and
   provide the administrator credential through the existing wizard. Verify
   fresh installation, cold boot, guest-agent shutdown, SSH host-key enrollment
   and network isolation. Preserve the exact verified ISO privately for rebuilds.
   The current guest is intentionally manual-start; keep that policy until
   reboot and recovery tests pass.

2. Configure an independent backup destination and test a full Windows restore.
   Reuse the existing cold backup implementation. It covers libvirt XML and all
   libvirt state, including disk, NVRAM and swtpm. Its canary restore is useful
   evidence but is not a Windows boot test. Restore into isolated paths and
   networking, with the required firmware and recovery material available.
   Coordinate this with the pending encrypted-storage migration.

3. Separate installation from ongoing Windows policy management. The current
   recipe fingerprint rejects old saved results, but rebuilding does not copy
   or apply new policy inside an installed guest. Add a bounded `apply-baseline`
   operation over pinned SSH, retain the previous public bundle, and report
   reboot requirements without automatically rebooting. Exclude disk creation,
   credential setup and installer-only driver steps from routine policy updates.

4. Add fresh compliance checks and drift reporting. Record applied policy hash,
   check time, failures and pending reboot separately. Compare owned fields in
   desired, persistent and live XML rather than raw XML, since libvirt adds
   defaults. Check the guest agent only while Windows runs. Reuse storage backup
   freshness reporting and notify on changed failures or expired evidence.

The current baseline checks both machine policy and `HKCU`. A check run through
the guest agent as SYSTEM must not interpret SYSTEM's user hive as the declared
administrator's hive. Split machine and user checks, or run the user portion in
the intended user's session. A saved PASS cannot establish current compliance.

Microsoft DSC is worth testing for repeated get/test/set operations once this
maintenance interface exists. DSC 3 does not supply a background local
configuration manager, so transport and scheduling still need an owner. See the
[DSC overview](https://learn.microsoft.com/en-us/powershell/dsc/overview?view=dsc-3.0).

### Retain the current manager

NixVirt can consolidate XML construction and reconciliation, but migration is
not the next improvement for one Windows guest. Its defaults can restart changed
active objects and remove objects omitted from managed lists. Any future trial
needs a pinned release, complete inventory, `restart = false`, `active = null`,
and disposable migration/restore tests. It would still need this repository's
Windows installer and restricted lifecycle interface. See the
[NixVirt project and options](https://github.com/AshleyYakeley/NixVirt).

Additional Linux VMs, Incus or Proxmox do not address the observed gaps. The
current workload has one Windows guest; ARM package builds already have binfmt
and a separate native builder path. See the [runbook](workstation-virtualization.md).

### Treat live backup consistency as a separate requirement

Installed virtnbdbackup 2.49 captures XML and firmware/NVRAM, but its inspected
[metadata implementation](https://github.com/abbbi/virtnbdbackup/blob/v2.49/libvirtnbdbackup/backup/metadata.py)
does not capture swtpm state. It also continues backup initiation after a failed
filesystem freeze. See its [freeze handling](https://github.com/abbbi/virtnbdbackup/blob/v2.49/libvirtnbdbackup/virt/fs.py)
and [backup initiation](https://github.com/abbbi/virtnbdbackup/blob/v2.49/libvirtnbdbackup/virt/client.py).
A successful command alone does not prove a coherent Windows backup.

Windows guest-agent freeze uses VSS with a limited freeze window. Do not freeze
the guest for the duration of a full disk copy. Use a coordinated backup API and
an independently tested TPM/recovery strategy before adding live incremental
backups. See the [QEMU guest-agent reference](https://www.qemu.org/docs/master/interop/qemu-ga-ref.html#command-guest-fsfreeze-freeze).

## Validation and limits

- The desktop system configuration evaluated successfully. The focused
  `virtualisation-configuration-contract` built on the desktop, validating
  generated XML, shell and PowerShell artifacts.
- All 16 focused Python VM tests passed, plus four subtests. Regression cases
  reproduced the pipeline, persistent-definition and autostart failures before
  the fixes. The tests use fixtures, not a running Windows installation.
- A temporary unprivileged copy of the built doctor, using libvirt's read-only
  connection, correctly identified active networks, pool, autostart and IOMMU
  groups. Its NOCOW check failed because that user could not read the directory
  attributes. The installed privileged helper independently confirmed NOCOW.
  This was not a complete passing privileged run of the new helper.
- The normal test-shell entry point was blocked by unrelated untracked Nix
  files during concurrent repository work. Focused Python tests used the same
  pinned nixpkgs source with explicit pytest and tool dependencies instead.
- Independent review found no actionable standards or correctness findings in
  this task's fixes. No full system build or activation occurred. No guest was
  started, stopped, installed, backed up or restored.

The next runtime acceptance step is activation followed by the installer and
recovery tests above. This review verifies host configuration and fixes specific
management defects; it cannot certify an uninstalled Windows workload.
