# Workstation virtualization runbook

Configuration date: 2026-09-04

## Decision

Keep NixOS on bare metal and use libvirt/QEMU/KVM as the desktop's only VM
manager. The current workload needs one persistent Windows 11 guest. It does
not need a Linux development VM, a full-system ARM VM, Incus, or Proxmox.

The resulting layout is:

```text
Ryzen desktop, NixOS
  |
  +-- native Linux applications and event-driven CPU work
  |
  +-- aarch64-linux package fallback
  |     binfmt + QEMU user-mode translation, no resident guest RAM
  |
  `-- windows-runtime
        libvirt + KVM, 4 unpinned vCPUs, 8 GiB RAM, 128 GiB qcow2
        persistent administrator desktop with autologon and UAC disabled
```

Use the M4's Determinate native Linux builder for larger `aarch64-linux`
builds when convenient. The desktop fallback starts QEMU only when an ARM
executable runs during a build. Nothing boots or reserves guest memory while
it is idle.

Incus would add a second QEMU owner without improving this Windows guest.
Proxmox is a bare-metal server distribution and would replace the NixOS
desktop. Neither belongs on this machine under the current requirements.

## What Nix owns

The reusable module interface is
`virtualisation.libvirtWorkstation`. The Windows-specific interface is
`virtualisation.libvirtWorkstation.windowsVm`. The desktop policy lives in
`hosts/nixos/desktop/local/security-virtualization.nix`.

Nix declares:

- the libvirt daemon, native-architecture QEMU package, swtpm, and management
  tools;
- one host-only management network and one NAT egress network;
- fixed guest MAC and IP addresses;
- guest-to-host and private-network egress firewall policy;
- the storage pool and root-only VM state directories;
- the Windows UUID, generation ID, machine ABI, disk serial, CPU, memory,
  firmware, TPM, display, storage, and network devices;
- the Windows release, edition, official source page, exact ISO filename, and
  Microsoft-published SHA-256;
- installer and runtime domain XML, both schema-validated during a Nix build;
- the public unattended Windows answer file and idempotent PowerShell
  baseline;
- the `headless-runtime` baseline profile and exact Appx removal selectors;
- a narrow, passwordless host helper for fixed lifecycle operations;
- the `vm`, `windows-vm`, and `setup-windows-vm` commands;
- on-demand `aarch64-linux` binfmt support.

Nix does not own the mutable Windows disk, TPM state, UEFI variables, ISO bytes,
administrator password, application data, or private provisioning payload.
A normal `nixos-rebuild` never creates, replaces, or deletes the Windows disk.

## Resource policy

The Windows guest starts with:

| Resource | Setting | Reason |
| --- | ---: | --- |
| vCPUs | 4 | Enough for two GUI applications and their agent without presenting the entire host |
| Memory | 8 GiB | Leaves roughly 22 GiB for NixOS, Codex, databases, caches, and burst calculations |
| Disk | 128 GiB sparse qcow2 | Practical capacity without allocating 128 GiB immediately |
| CPU shares | 512 | A busy guest yields to ordinary host work under contention |
| Autostart | Off | The workstation decides when to pay the 8 GiB memory cost |

The vCPUs are not pinned. They can run on any idle host CPU, and inactive
vCPUs reserve no core. The configuration does not reserve hugepages or isolate
host CPUs. The host calculation worker can therefore use every core when it
has work. Linux scheduling and the lower guest share weight preserve desktop
responsiveness when both workloads are busy.

Guest RAM is a real standing cost whenever Windows runs. Start at 8 GiB and
measure committed memory inside Windows before raising it. Do not reduce host
headroom based on an idle observation.

While `windows-runtime` is active, a lifecycle hook holds a sleep inhibitor so
Hypridle cannot silently suspend its network connection. The inhibitor does
not block an orderly host shutdown, and it is released when the QEMU process
exits. `vm doctor windows-runtime` verifies both directions of that state.

## Security model

The Windows runtime intentionally uses a local Administrator account,
automatic console logon, and `EnableLUA=0`. Every process in that session gets
the full administrator token. This is an accepted requirement, not a security
default hidden by the module.

The controls outside the guest remain strict:

- QEMU runs as the unprivileged `qemu-libvirtd` account with seccomp enabled;
- libvirt has no TCP or TLS management listener;
- the operator is not a member of `libvirtd`, `kvm`, `disk`, or a VFIO group;
- the management interface is host-only;
- the NAT interface can reach public IPv4 addresses but cannot initiate
  connections to RFC 1918, shared, loopback, link-local, multicast, or
  reserved IPv4 ranges;
- Windows OpenSSH accepts Ed25519 keys only and permits port 22 solely from
  `192.168.123.1`;
- SPICE uses a local Unix socket, with clipboard and file transfer disabled;
- there are no host filesystem shares, USB redirection devices, audio devices,
  forwarded credentials, or nested virtualization;
- Defender, Windows Firewall, Windows Update, Event Log, Task Scheduler, WMI,
  PowerShell, .NET, WebView, and the QEMU guest agent remain installed;
- the seed builder rejects symlinks and special files in the private payload;
- passwords never enter a Nix derivation, Git file, Nix store path, or host
  command argument. Sysinternals receives the password briefly as a
  guest-local process argument while it writes the LSA secret.

UAC being disabled means malicious or compromised guest software can control
the whole Windows installation and read its live credentials. The network and
hypervisor controls reduce the damage outside the VM, but they cannot restore
privilege separation inside Windows.

## Public and private configuration

The public repository contains no application or account names. Optional
private automation goes in:

```text
/var/lib/libvirt/private/windows-runtime/
```

The directory is writable only by the explicit Windows VM provisioning group.
It may contain an `Install.ps1` entry point plus private payload files. The
public bootstrap calls it as:

```powershell
Install.ps1 -AdministratorName vmadmin -ManagedRoot C:\ProgramData\ManagedVm
```

Keep credentials in a private secret manager or encrypted payload. The host
directory itself is not a substitute for encryption. The setup process copies
the payload into the guest, where it becomes durable private state.

The private workload research note is intentionally ignored by Git. Do not
rename or move its contents into a tracked public document.

## Windows baseline

The unattended setup selects `Windows 11 Pro` from Microsoft's production
Windows 11 25H2 multi-edition x64 ISO and installs with UEFI Secure Boot,
TPM 2.0, and a stable virtual hardware identity. The ISO recipe pins the exact
`Win11_25H2_English_x64_v2.iso` filename and Microsoft's published SHA-256.
The installer
initially presents the system disk through SATA so Windows Setup can use its
built-in storage driver. A small temporary VirtIO disk primes the VirtIO SCSI
driver. Finalization switches the system disk to VirtIO SCSI for normal
operation.

The public PowerShell baseline:

- installs the pinned VirtIO storage, network, serial, balloon, RNG, input,
  and display drivers;
- installs and starts the QEMU guest agent;
- installs OpenSSH Server, disables password login, and applies restrictive
  authorized-key ACLs;
- stores permanent autologon credentials with Microsoft's pinned and
  Authenticode-verified Sysinternals Autologon tool;
- disables OOBE Express settings while explicitly keeping Windows and Edge
  SmartScreen enabled;
- disables sleep and hibernation while keeping the logical display active;
- uses the balanced power plan and a system-managed page file;
- sets Windows Update active hours through the supported policy path, keeps
  automatic servicing enabled, and schedules Defender scans for 02:00;
- disables Game DVR, supported Pro suggestion policies, widgets, and peer
  update delivery;
- enables Win32 long paths and disables the redundant Automatic Restart
  Sign-On credential mechanism;
- prevents Edge background mode and Startup Boost without removing Edge or
  WebView2;
- reduces shell animation, taskbar, and search UI overhead while keeping the
  desktop usable for emergency debugging;
- disables unused nested-virtualization, PowerShell 2, and SMB1 features;
- removes only the Appx package selectors declared in the host policy and
  fails if a present selected package remains installed or provisioned;
- keeps a local retry entry until both the public baseline and optional
  private hook pass;
- writes a machine-readable status file and a structured JSON-lines step log;
- stamps status with a hash of the public answer file, scripts, media identity,
  and baseline policy. Host commands reject a stale `PASS` from an older
  recipe.

It does not run a third-party debloat script or disable Windows security,
update, management, WebView, or application-installation infrastructure.
Dormant packages mostly cost disk space, not steady CPU, so the removal list
is intentionally conservative. The detailed upstream comparison and rejected
options are in
[`unattend-generator-feature-research.md`](unattend-generator-feature-research.md).

The guest may reboot for updates outside the declared 05:00-23:00 active
window. The baseline intentionally does not set
`NoAutoRebootWithLoggedOnUsers`: permanent autologon would otherwise let that
policy defer security-update restarts indefinitely. Sysinternals Autologon
restores the declared administrator session after an ordinary restart; private
application startup still needs its own tested Task Scheduler policy.

## Deploying the host configuration

This repository change has not been deployed. From the Mac, build or deploy
the desktop through deploy-rs so the desktop performs the build:

```sh
just desktop-build   # remote build and dry activation
just desktop-deploy  # remote build and activation
```

The deploy node also keeps `deploy .#desktop` safe by setting
`remoteBuild = true`. Do not run a plain
`nix build .#nixosConfigurations.desktop.config.system.build.toplevel` from
the Mac because that command has no deploy node context and can select the
native Linux builder. The `just os-* desktop` commands reject execution unless
the local hostname is `desktop`.

Log out and back in on the desktop so the new `libvirt-media` and
`windows-vm-provisioning` memberships enter the login session. Then run:

```sh
vm doctor
vm list
windows-vm plan
```

The NixOS activation defines the networks, storage pool, and inactive Windows
domain. It does not download Windows, create a disk, or start the VM.

## Installing Windows

Run the interactive setup on the NixOS desktop:

```sh
windows-vm setup
```

The wizard performs six reviewed stages:

1. Open Microsoft's public Windows 11 download page, select the 25H2
   multi-edition x64 ISO in English (United States), and stage it.
2. Authorize the desktop's generated Ed25519 key and any additional trusted
   administrator key.
3. Pause for the optional private `Install.ps1` payload.
4. Display the immutable paths, resources, and current state before mutation.
5. Collect the administrator password into `/run`, create a new disk only if
   none exists, and start unattended installation.
6. Require a `PASS` status from the guest agent, shut Windows down cleanly,
   select the VirtIO runtime definition, cold-boot it, and verify that the
   guest agent returns before removing the recovery marker.

Microsoft's generated production ISO URL expires after 24 hours, so committing
that URL would make the build fail the next day. The stable declaration is the
release, image name, filename, source page, and Microsoft-published SHA-256.
The ISO is downloaded once and retained in the private host media directory.
The wizard hashes the downloaded bytes and the privileged
preflight exposes the verified ISO through a read-only userspace filesystem
under a dedicated unprivileged account. It does not ask the host kernel to
parse operator-supplied ISO filesystems. The preflight rejects the file unless
`install.wim` or `install.esd` contains the declared
`Windows 11 Pro` image. This catches the wrong edition or media before the VM
disk is created. The staged path is:

```text
/var/lib/libvirt/boot/Win11_25H2_English_x64_v2.iso
```

Back up that exact verified ISO to a private artifact location if this VM must
remain rebuildable after Microsoft replaces 25H2 on the public page. Do not put
Windows media in Git or a public Nix cache. The font package uses the public
Enterprise Evaluation channel, and the LTSC link on that same Evaluation
Center is also 90-day media. Neither is an activatable production substitute.

The production installation may remain unactivated during provisioning. Apply
the existing key later inside the guest; never add it to the Nix module,
answer-file template, shell history, or public private-overlay scaffold.

The temporary password and answer ISO live below `/run/libvirt-workstation`.
The guest deletes the transient password and cached answer file after
`oobeSystem`; the host removes the answer ISO during finalization. Volatile
host copies also disappear on reboot. If the host reboots during Windows
Setup, enter the same administrator password again and run:

```sh
windows-vm resume
```

The installer credential must be at least 16 printable ASCII characters, begin
with a letter or digit, contain no whitespace, and use at least three of
lowercase, uppercase, digits, and symbols. These constraints keep Windows
Setup, XML, PowerShell, and the native Autologon command unambiguous.

The wizard is safe to rerun. `windows-vm phase` distinguishes a new guest,
an active or interrupted installer, and a finalized runtime. The unattended
wait has a 45-minute bound and returns the guest's failure detail if the public
baseline or private hook fails.

The fresh installer refuses to proceed if
`/var/lib/libvirt/images/windows-runtime.qcow2` already exists. It never
overwrites a deployed VM. Before boot, it also proves that the installer XML
has one writable SATA system disk, one read-only driver-prime disk, and three
read-only optical media. It verifies that the created system disk is qcow2,
has the declared virtual size, and has no backing file. To abandon only an
incomplete marked installation, run `windows-vm discard` and type the full
confirmation phrase.

## Routine operation

Use the small host interfaces rather than general passwordless libvirt access:

```sh
vm list
vm doctor windows-runtime
vm start windows-runtime
vm status windows-runtime
vm ip windows-runtime
vm ssh windows-runtime
vm gui windows-runtime
vm stop windows-runtime

windows-vm plan
windows-vm phase
windows-vm verify-media
windows-vm wait-baseline
windows-vm baseline
windows-vm provisioning-log
windows-vm provisioning-log-previous
windows-vm host-key
```

The provisioning log is JSON Lines with a run ID, step name, result, duration,
and failure detail. A retry rotates the current log to
`provisioning-steps.previous.jsonl`, so the prior failure remains available
through `windows-vm provisioning-log-previous` instead of corrupting or being
mixed into the next attempt.

`vm stop` requests graceful shutdown. No force-off or delete operation is in
the routine helper. General changes still require an interactive Polkit
authorization in virt-manager.

Retrieve the Windows Ed25519 host key through the libvirt guest-agent channel,
verify its fingerprint, and add it under `windows-runtime` to the desktop and
Mac `known_hosts` files. Both SSH definitions use strict host-key checking and
disable password login and agent forwarding.

## ARM package builds

The desktop advertises `aarch64-linux` as an emulated Nix platform. Build an
ARM flake output directly when the M4 is unavailable:

```sh
nix build .#packages.aarch64-linux.<package>
```

This is slower than native Apple Silicon, but it has no idle VM cost. There is
no `arm-smoke` domain and no full `qemu-system-aarch64` installation.

## Moving to server mode

After the desktop becomes an unattended server, set:

```nix
virtualisation.libvirtWorkstation.windowsVm.autostart = true;
```

Do that only after testing cold host boot, automatic Windows logon, private
application startup, Windows Update reboot, loss and restoration of network,
guest-agent shutdown, and ambiguous external-operation recovery. The existing
module will then reconcile libvirt autostart instead of requiring a new VM
definition.

## Backups and recovery

No scheduled backup is enabled because the repository does not declare an
independent destination, retention policy, or recovery-key store. Do not call
snapshots backups. A recoverable Windows backup must capture, together:

- the qcow2 disk;
- inactive libvirt XML;
- UEFI NVRAM;
- swtpm state;
- the stable UUID and generation ID;
- private recovery and application material.

Take crash-consistent copies only while the guest is shut down, or use a
guest-coordinated backup method. Test a restore before the VM becomes required
for unattended operation.

GPU passthrough remains disabled. The VFIO configuration block records the
host-local RTX functions for a possible later project, but the normal NixOS
boot owns the GPU and the Windows domain has no PCI host device. Enabling the
host profile alone is intentionally insufficient; adding the guest `hostdev`,
display, reset, and recovery policy remains a separate reviewed change.

## Verification

The focused repository contract runs on the desktop host:

```sh
nix build --store ssh-ng://root@desktop \
  .#checks.x86_64-linux.virtualisation-configuration-contract --no-link
```

It evaluates the real desktop and Mac configurations, validates both libvirt
domain XML files and both network XML files, lints the generated shell tools,
parses the generated PowerShell and unattended answer file, and tests secret
rendering, printable-ASCII enforcement, XML escaping, file permissions,
multiline rejection, fingerprint consistency, disk topology, and symlink
rejection. Build the complete desktop closure only with `just desktop-build`,
which also builds it on `desktop`.
