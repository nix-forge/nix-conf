# Workstation virtualization architecture research

Research date: 2026-09-03

Implementation note: the completed configuration and staged operating
procedure are in `docs/workstation-virtualization.md`. The final module keeps
guest domain XML and disks as deliberate mutable libvirt state, with a typed
lifecycle allowlist and declarative network, storage, access, and VFIO policy.
This is narrower than the exploratory domain-declaration interface considered
later in this research record. The M4 already has Determinate's native Linux
builder, so the final configuration adds no second Mac VM manager.
The runbook supersedes the exploratory recommendations below: there is no ARM
system VM, Windows has no passed-through GPU, and the recorded VFIO profile is
disabled.

## Recommendation

Keep NixOS on bare metal and use one libvirt/QEMU control plane on the Ryzen
desktop. Use KVM for x86-64 Linux and Windows, and use a reboot-selected VFIO
profile when Windows needs the RTX 4070. Keep the AMD Raphael iGPU attached to
the NixOS host so the desktop, recovery console, and remote access remain
available while Windows owns the discrete GPU.

Do not install Proxmox VE on this workstation and do not put Proxmox inside a
VM. Do not add Incus yet. Incus becomes worthwhile only if a later requirement
calls for a fleet of Linux system containers, profiles, projects, and its API.
Rootless Docker already owns the application-container role in this repository.

The ARM requirement uses two execution paths:

1. Provide a small, trusted `aarch64-linux` QEMU/TCG guest on the desktop for
   local smoke tests and boot testing. It will be emulated, not KVM accelerated.
2. Use the Apple M4 Pro MacBook for normal ARM builds. Its existing Determinate
   native Linux builder handles `aarch64-linux`, and the Mac host handles
   `aarch64-darwin`.

This is the smallest architecture that satisfies the performance, security,
licensing, Windows passthrough, and Codex UX requirements:

```text
Codex UI
  |
  +-- concrete SSH alias: desktop
  |     `-- NixOS x86-64, source of truth and primary workspace
  |           +-- libvirt/KVM: Windows 11 x86-64
  |           |     `-- optional RTX 4070 VFIO boot profile
  |           +-- libvirt/KVM: x86-64 test guests
  |           `-- QEMU/TCG: trusted ARM64 Linux smoke-test guest
  |
  `-- local Nix on the Apple M4
          +-- macOS host: aarch64-darwin
          `-- Determinate native Linux builder: aarch64-linux
```

There is no supported single physical-machine design using the hardware in
this repository that provides both macOS execution and RTX 4070 passthrough.
The Ryzen PC cannot legally host macOS, and the M4 MacBook cannot physically
own the desktop's PCIe GPU. The desktop can still be the main development
machine because it owns the workspace and orchestration. The Mac handles
architecture-specific builds.

## What the repository and hardware already provide

The repository supports the proposed split well:

- `hosts/nixos/desktop/default.nix` declares an `x86_64-linux` desktop and
  already imports the local security virtualization policy.
- `hosts/nixos/desktop/local/security-virtualization.nix` deliberately leaves
  libvirt and VFIO disabled until the Windows device, storage, network, and
  recovery design is known. That caution is correct.
- `modules/nixos/virtualisation/libvirt.nix` is an unused early stub. It uses
  `pkgs.qemu_kvm`, runs QEMU as root, trusts `virbr0` and `br0` globally, and
  installs broad VFIO udev rules. It should be replaced rather than enabled.
- `modules/nixos/virtualisation/docker.nix` already gives application
  containers a rootless home. Incus does not need to duplicate that job.
- `flake.nix` evaluates `x86_64-linux`, `aarch64-linux`, and
  `aarch64-darwin`, so the flake is ready to describe all three execution
  systems.
- `homes/macbook-pro-m4/local/dev-vm.nix` already has a useful model for a
  concrete SSH alias, strict host-key checking, private VM reachability, and a
  declarative tunnel. Keep the existing VMware Fusion Windows ARM path until
  the new guests are proven rather than replacing it during the first rollout.
- `docs/codex-desktop-remote-ssh-nushell-research.md` documents the current
  Codex Remote Connection setup and its Bash login-shell requirement.

A read-only inspection of `desktop` on 2026-09-03 found:

| Resource | Observed state | Design consequence |
| --- | --- | --- |
| CPU | Ryzen 7 7700X, 8 cores and 16 threads, SVM and NPT present | Strong KVM host, but not an ARM CPU |
| Memory | 30 GiB usable | Windows and one development guest are comfortable; concurrent heavy guests need limits |
| Discrete GPU | RTX 4070 `10de:2786` plus audio `10de:22bc`, together and alone in IOMMU group 12 | A clean VFIO unit without an ACS override |
| Host GPU | Raphael iGPU `1002:164e` plus audio `1002:1640` | Viable host display and recovery path during RTX passthrough |
| Current graphics ownership | `nvidia` owns the RTX; `amdgpu` owns the iGPU | The host graphical session and Sunshine must move to the iGPU before VFIO binding |
| Storage | 945 GiB Btrfs system filesystem with about 479 GiB free; 1.3 TiB Btrfs games filesystem with about 708 GiB free | Enough space, but VM image COW policy must be chosen at creation |
| At-rest encryption | The system Btrfs filesystem is directly on the NVMe partition in the observed layout | Sensitive VM disks need host-disk encryption or deliberate guest encryption before use |
| FireWire | Prior repository notes record IOMMU faults; its group also contains upstream bridge devices | Leave it on the host and out of passthrough scope |

These observations should be rechecked at activation time. PCI addresses and
IOMMU groups are hardware facts, not portable module defaults. The Linux VFIO
documentation treats the IOMMU group as the minimum ownership and isolation
unit, so every device function in a selected group must be accounted for.
[The kernel VFIO documentation](https://www.kernel.org/doc/html/latest/driver-api/vfio.html)
explains the group model.

## The hard boundary around ARM macOS

The macOS Tahoe 26 license permits up to two additional macOS instances in
virtual operating-system environments on each Apple-branded computer already
running macOS, including for software development and development testing. The
same license says the software may not be installed or run on a non-Apple-
branded computer. See sections 2B(iii) and 2J in
[Apple's current macOS Tahoe license](https://www.apple.com/legal/sla/docs/macOSTahoe.pdf).
This is a direct license constraint, not a hypervisor feature gap. It is not
legal advice, but it is clear enough that this repository should not automate a
macOS guest on the Ryzen PC.

Apple documents macOS guests through
[Virtualization.framework on a Mac](https://developer.apple.com/documentation/virtualization/virtualize-macos-on-a-mac)
and installation from an Apple restore image in
[Installing macOS on a virtual machine](https://developer.apple.com/documentation/virtualization/installing-macos-on-a-virtual-machine).
The existing M4 Pro MacBook is therefore the correct legal and technical ARM
host if an isolated macOS VM becomes necessary. The current requirement is
architecture-native building, not isolated OS testing, so this repository does
not provision a macOS guest. That avoids another VM lifecycle, image, key, and
backup system.

For `aarch64-linux`, the Mac's existing Determinate native Linux builder is the
normal build environment. Use the Mac host itself for `aarch64-darwin`. The
builder is local to the Mac's Nix daemon. The desktop can offload derivations to
the Mac only after a separate authenticated remote-builder path exists. Nix's
setup guide recommends a dedicated build user and pinned public host keys. See
the [Nix distributed-build guide](https://nix.dev/tutorials/nixos/distributed-builds-setup.html)
and [remote-build reference](https://nix.dev/manual/nix/latest/advanced-topics/distributed-builds).

## Why the desktop ARM guest is a fallback

QEMU can emulate an AArch64 system on x86-64. Its manual includes an AArch64
`virt` machine with a `max` CPU and TCG acceleration, and its supported-target
table includes ARM system emulation. See the
[QEMU system introduction](https://www.qemu.org/docs/master/system/introduction.html)
and [emulation target table](https://www.qemu.org/docs/master/about/emulation.html).
KVM cannot accelerate a different instruction-set architecture, so this guest
will translate ARM instructions in software.

This is more than a performance caveat. QEMU's security policy classifies TCG
as a non-virtualization use case and says users must not rely on it for guest
isolation or security guarantees. The supported virtualization boundary
requires an accelerator such as KVM or HVF. See
[QEMU's security requirements](https://www.qemu.org/docs/master/system/security.html).
Consequently, the desktop ARM guest must be limited to trusted, pinned NixOS or
Linux images and disposable tests. It must not become the sandbox for
untrusted code. Determinate's native Linux builder on the M4 is the normal path
for ARM builds.

The pinned NixOS libvirt module already encodes the packaging distinction:
`pkgs.qemu` can emulate alien architectures, while `pkgs.qemu_kvm` keeps only
host architectures. It also currently defaults to running QEMU as root and
disables QEMU namespaces, both of which the replacement module must override or
test deliberately. See the
[pinned NixOS libvirt options](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/nixos/modules/virtualisation/libvirtd.nix#L47-L120).

## Platform decision

| Criterion | libvirt/QEMU on NixOS | Incus on NixOS | Proxmox VE |
| --- | --- | --- | --- |
| Fits the current bare-metal NixOS desktop | Yes | Yes, but adds a second manager | No; its supported role is a Debian-based hypervisor appliance |
| x86-64 Windows and Linux | Best fit; direct domain XML and mature KVM tooling | Supported through QEMU | Excellent on a dedicated host |
| ARM Linux on this x86 host | Explicit QEMU/TCG guest is possible | Current Incus VM flow is same-architecture virtualization | Current Proxmox requires guest and node architectures to match |
| ARM macOS on this PC | Technically out of scope and license-incompatible | Same | Same |
| RTX passthrough control | Direct VFIO and libvirt `hostdev` control | Physical GPU passthrough exists, with less direct Windows tuning | Strong, but only if Proxmox owns bare metal |
| Linux system-container fleet | Not its job | Best option | Strong LXC integration |
| Declarative fit for this repo | Strong with a small Nix reconciliation layer | NixOS preseed is initialization, not complete desired state | Weak; it moves the host outside this NixOS configuration |
| Recommended role | Primary desktop hypervisor | Add later only for a proven system-container need | Separate server alternative, never a layer here |

### Libvirt is the right primary layer

Libvirt exposes KVM acceleration, QEMU TCG emulation, system-level PCI and TAP
access, domain XML, networks, storage, TPM devices, and mature graphical tools
without changing the host operating system. Its system instance is appropriate
because PCI assignment and managed host networking need privilege, while each
QEMU process can still drop to an unprivileged account. Libvirt explicitly
distinguishes the unprivileged session instance from the system instance used
for PCI, block, USB, and network resources in its
[QEMU driver documentation](https://libvirt.org/drvqemu.html).

Use libvirt as the only desktop VM control plane. Do not launch independent
QEMU processes for one guest and libvirt domains for another. One inventory,
one network owner, and one device owner make lifecycle and recovery legible.

### Incus is a conditional later addition

Incus is strongest when the desired abstraction is a small private cloud of
Linux system containers, images, profiles, projects, and API-managed
instances. Its system containers share the host kernel and have low overhead;
its VMs are implemented with QEMU and currently expose fewer Incus features
than containers. See
[Incus instance types](https://linuxcontainers.org/incus/docs/main/explanation/instances/).

It does not solve cross-architecture ARM on this host. Incus documents VM
guests in terms of the host architecture and its 32-bit personality, and a
project maintainer confirms that the normal VM path virtualizes the same
architecture rather than invoking QEMU CPU emulation. See the
[Incus architecture documentation](https://linuxcontainers.org/incus/docs/main/architectures/)
and the [maintainer answer on ARM64 guests on x86-64](https://discuss.linuxcontainers.org/t/arm64-container-vm-on-x86-64-host/19583).

Incus can pass a physical GPU to a VM, but it cannot hotplug a physical VM GPU.
That does not improve the boot-time ownership problem on this desktop. See the
[Incus GPU device reference](https://linuxcontainers.org/incus/docs/main/reference/devices_gpu/).

The current storage layout is also a poor default for an Incus VM pool. Incus
explicitly says not to use VMs with Btrfs storage pools because random I/O and
qgroup accounting can exhaust quota. See its
[Btrfs storage warning](https://linuxcontainers.org/incus/docs/main/reference/storage_btrfs/).
A future Incus deployment should therefore get a separate LVM or ZFS pool,
not a loop-backed pool on the existing Btrfs filesystem.

Do not place the daily user in `incus-admin`. Incus says local Unix-socket
access can attach host paths and devices or change instance security, and
should be given only to users trusted with root. Its restricted `incus` user
socket is the better starting point if the platform is added. See
[Incus local access control](https://linuxcontainers.org/incus/docs/main/installing/#manage-access-to-incus).

The NixOS Incus module's `preseed` is useful for bootstrap but is not a full
reconciler: it creates or overwrites declared objects and intentionally does
not remove undeclared ones. See the
[pinned NixOS Incus module](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/nixos/modules/virtualisation/incus.nix#L182-L307).
That behavior is sensible for stateful infrastructure, but it does not justify
adding Incus for two workstation VMs.

If Incus is added later, keep it beside libvirt rather than above it. Give it a
separate storage pool, subnet, bridge namespace, and device inventory. Never
let both managers claim the RTX GPU or the same disk image.

### Proxmox belongs on a separate appliance

Proxmox VE combines KVM, LXC, storage, networking, backups, clustering, and a
web interface. Those are excellent features for a dedicated server. Proxmox's
[current administration guide](https://pve.proxmox.com/pve-docs/pve-admin-guide.pdf)
describes its Debian base and bare-metal installation model. Replacing this
NixOS workstation with it would make the interactive desktop, Hyprland,
Sunshine, gaming, rootless development services, and host policy guests of an
appliance-oriented stack. Installing it alongside NixOS is not a supported
hybrid.

Proxmox VE 9.2 now has an official ARM64 host edition, but that does not make
the Ryzen host an ARM execution node. Proxmox states that guests run only on
nodes of matching architecture. See the
[official ARM64 release](https://www.proxmox.com/en/about/company-details/press-releases/proxmox-virtual-environment-launches-official-arm64-support)
and its [architecture-specific announcement](https://forum.proxmox.com/threads/proxmox-virtual-environment-now-available-for-64-bit-arm-arm64.185527/).

Running Proxmox as a nested KVM guest would add a second control plane and an
extra failure boundary without enabling macOS or faster ARM emulation. Nested
KVM is useful for hypervisor testing, not for this production path. The Linux
kernel also warns that, on AMD, saving or migrating an L1 guest while it has a
live L2 guest can leave the result unstable and insecure. See
[the kernel nested-KVM guide](https://www.kernel.org/doc/html/latest/virt/kvm/x86/running-nested-guests.html).
Keep nesting off unless a bounded hypervisor test specifically needs it.

## Desktop libvirt design

### Service posture

The replacement module should set these non-negotiable defaults:

- Use `virtualisation.libvirtd` with the system connection because VFIO and
  managed networks require it.
- Set `qemu.package = pkgs.qemu` so the AArch64 system emulator exists.
- Set `qemu.runAsRoot = false`. Libvirt strongly recommends against root QEMU
  processes and can arrange access to assigned devices and disks for its QEMU
  service account. See the
  [libvirt QEMU privilege model](https://libvirt.org/drvqemu.html#posix-users-groups).
- Enable `swtpm`, but attach a TPM only to guests that need it.
- Set `allowedBridges = []` unless a session guest has a reviewed bridge need.
  The pinned NixOS module otherwise installs a setuid bridge helper and allows
  `virbr0` by default.
- Set `onBoot = "ignore"`, keep every guest's autostart off, and set
  `onShutdown = "shutdown"`. A workstation reboot must not silently restore a
  Windows guest that expects a GPU now owned by the host.
- Leave the libvirt D-Bus bridge and network listeners disabled. Local Unix
  socket plus SSH is sufficient.
- Keep libvirt's nftables backend. Do not mark a VM bridge as a globally
  trusted NixOS firewall interface.
- Keep seccomp, capability dropping, cgroup device filtering, and a security
  driver enabled. QEMU's security architecture recommends an unprivileged
  process plus namespaces, seccomp, and mandatory access control as layered
  defenses. See [QEMU security architecture](https://www.qemu.org/docs/master/system/security.html)
  and [libvirt's security-driver description](https://libvirt.org/drvqemu.html#driver-security-architecture).

The pinned NixOS module writes `namespaces = []` unless overridden. Do not
claim namespace confinement without changing and testing that setting. Start
by testing libvirt's mount namespace with firmware, swtpm, the guest agent,
and VFIO. Verify the effective QEMU UID, capabilities, seccomp state, cgroup,
and libvirt security label after boot. If AppArmor sVirt is selected, verify a
per-domain enforcing profile exists; merely enabling AppArmor on the host is
not proof that the domain is confined.

Treat system-libvirt management as host administration. A controller can
define a domain that attaches host block devices, PCI devices, or paths. Do not
add the ordinary Codex development user to `libvirtd` for passwordless access.
Use the existing polkit path for deliberate interactive administration and
small root-owned systemd units for narrowly scoped operations such as starting
or stopping one named domain. Codex should be able to use `vm status`, `vm ssh`,
and guest consoles without gaining a general host-device attachment API.

### Network model

Use libvirt NAT and isolated networks, not a bridge to the physical LAN:

- `dev-mgmt`: host-only/isolated subnet with fixed DHCP reservations. It gives
  each guest a stable SSH address even when egress is disabled.
- `dev-nat`: private RFC 1918 subnet with outbound NAT. It has no inbound port
  forwards and is attached only to guests that need internet access.
- `quarantine`: optional isolated subnet for installers or untrusted media.

For a guest with both management and NAT interfaces, make `dev-nat` the only
default route and DNS source. The management interface exists only for stable
host-to-guest access. Give the guest firewall an explicit SSH rule for the
management subnet so Windows network-profile changes do not silently break the
Codex path.

Libvirt's isolated network has no physical-LAN forwarding, while its NAT mode
allows outbound connections and rejects unsolicited inbound traffic. See the
[libvirt network format](https://libvirt.org/formatnetwork.html) and
[firewall behavior](https://libvirt.org/firewall.html).

Give every guest a declared MAC address and DHCP reservation. Permit only
DHCP, DNS, ICMP needed for diagnostics, and the chosen SSH path on the host
firewall. Do not trust `virbr0`, `br0`, or any generated bridge wholesale.
Do not expose SPICE, VNC, libvirt TCP, QMP, or an HTTP management UI to the LAN.

For Codex, publish concrete SSH aliases such as `desktop`, `linux-dev`,
`arm-smoke`, and `windows-dev`. Pin a distinct host key and identity for each.
The Mac reaches the desktop's host-only guest addresses through the existing
`desktop` jump host. OpenAI's
[Remote Connection documentation](https://learn.chatgpt.com/docs/remote-connections)
says Codex discovers concrete SSH aliases, starts its remote process through
the login shell, and recommends trusted keys, least privilege, and VPN or mesh
reachability instead of exposing a separate app server.

Do not mount the whole host project tree read-write into every guest. A guest
compromise would then have a direct path to source, credentials, and Git
metadata. Prefer a Git checkout inside each development guest and move changes
over SSH. If a shared directory is genuinely better for a trusted guest,
declare the smallest project path, make source read-only where possible, and
exclude `.ssh`, secret stores, and agent sockets. Libvirt documents the
virtiofs host-directory mechanism in its
[virtiofs guide](https://libvirt.org/kbase/virtiofs.html).

### Storage model

Keep mutable VM state outside the Nix store. Domain and network descriptions
are declarative; disk images, UEFI variable stores, TPM state, and installation
media are runtime state. A good initial layout is:

```text
/var/lib/libvirt/
  images/<guest>/disk.raw-or-qcow2
  qemu/nvram/<guest>.fd
  swtpm/<guest>/...
  backups/<guest>/manifest.json
```

Use the system NVMe, not the shared native-Windows/game partitions, for the
first Windows image. Create a dedicated NOCOW directory before the first byte
is written. QEMU warns that Btrfs performs poorly for VM images, especially
when the guest also uses Btrfs, and its `nocow=on` option works only for a new
or empty file. See [QEMU disk-image options](https://www.qemu.org/docs/master/system/images.html).

Choose the disk format per guest:

- Windows performance profile: preallocated raw file in the NOCOW directory.
  Raw is simple and avoids qcow2 metadata overhead. Back it up while the guest
  is shut down.
- Disposable Linux and ARM smoke-test guests: qcow2 with metadata
  preallocation in the NOCOW directory, when backing images and snapshots are
  worth the extra metadata layer.
- Future high-I/O Windows profile: a dedicated added NVMe or logical volume.
  Do not pass the existing whole Samsung controller because it also owns host
  partitions.

NOCOW gives up Btrfs data checksumming and compression for those files, so it
is a performance choice, not free optimization. The
[Btrfs administration documentation](https://btrfs.readthedocs.io/en/stable/Administration.html)
describes that trade. Test the restore. A backup that has never been restored
is still a guess. A Windows backup must keep its disk, UEFI NVRAM, virtual TPM
state, domain identity, and BitLocker recovery material consistent. Store
recovery keys outside both the VM and its backup. Do not keep active VM state
under `/tmp`; this host intentionally uses tmpfs there.

The observed host filesystem is not currently backed by a visible dm-crypt
layer. Complete the planned host-disk encryption before putting durable source
secrets in guest images. Guest BitLocker or LUKS remains useful, but a virtual
TPM stored beside the virtual disk does not replace host at-rest encryption.

### Windows guest

Start Windows without passthrough. Use a Q35 machine, UEFI Secure Boot-capable
firmware, TPM 2.0 through swtpm, VirtIO storage and networking, a serial channel
or SPICE console, and the QEMU guest agent. Windows 11 lists UEFI/Secure Boot
capability and TPM 2.0 among its minimum requirements in
[Microsoft's Windows 11 requirements](https://support.microsoft.com/en-us/windows/windows-11-system-requirements-86c11283-ea52-4782-9efd-7674389a7ba3).
Keep installation media and VirtIO drivers pinned by source and hash.

Begin with 6 cores/12 threads and 12 to 16 GiB of RAM, leaving at least two
physical cores and roughly 10 GiB for NixOS, Codex, networking, and the iGPU
desktop. Use host-passthrough CPU mode for this single-host guest. Do not
reserve static hugepages or pin CPUs in the baseline. Measure compile, game,
audio, and host-interactivity latency first; then pin whole SMT sibling pairs
and emulator/I/O threads if the measurements justify it.

### RTX 4070 passthrough

Use two NixOS boot profiles rather than live-detaching the active desktop GPU:

- `default`: NVIDIA owns `01:00.0` and its audio function; Windows uses an
  emulated display or remote desktop.
- `windows-vfio`: the AMD iGPU owns the host display from early boot; VFIO owns
  both RTX functions in IOMMU group 12; the Windows domain may attach both.

The Windows domain keeps the same UUID, disk, NVRAM, TPM state, and network
identity across profiles. Only its graphics devices differ, and it must be off
when the persistent definition changes. Libvirt's managed PCI `hostdev` mode
can detach and restore devices around a domain, but it cannot safely detach a
GPU that the compositor, NVIDIA driver, or Sunshine is actively using. See the
[libvirt host-device format](https://libvirt.org/formatdomain.html#host-device-assignment).

Before enabling the VFIO profile:

1. Connect a display to the motherboard output and prove the full NixOS login,
   SSH, rollback, and Sunshine path on the Raphael iGPU.
2. Enable SVM/IOMMU and Above 4G Decoding in firmware. Record the ReBAR setting
   used for the successful test rather than assuming either value.
3. Recheck that group 12 contains only `01:00.0` and `01:00.1` and bind both by
   exact PCI IDs or addresses. Do not add an ACS override; none is needed.
4. Keep the FireWire device and all unaudited USB controllers on the host.
5. Boot Windows first with its virtual display still available, install the GPU
   driver, and only then test the physical RTX output.
6. Repeat cold boot, warm reboot, guest shutdown/start, host suspend policy,
   and failed-guest recovery tests. A successful first boot does not prove the
   GPU resets reliably.

Do not autostart the VFIO guest. Refuse to start it outside the VFIO boot
profile, and refuse to switch profiles while it is running. Keep one known-good
NixOS generation whose initrd does not bind the RTX to VFIO.

## ARM build design on the Mac

Keep the existing Determinate integration as the only added ARM build
mechanism. The Darwin module sets
`determinateNix.determinateNixd.builder.state = "enabled"`, which provides the
native `aarch64-linux` builder. The Mac host builds `aarch64-darwin` outputs.

This path has no user-managed guest disk, installer, VM SSH identity, or VM
network. It also does not provide a general interactive Linux machine or an
isolated macOS test machine. Add either capability only when a test needs an OS
boundary that a Nix build does not provide.

The desktop's TCG guest remains useful for ARM boot tests. It is not a
performance substitute for the M4 builder and does not become a trust boundary
for untrusted code.

## Nix module boundary

Keep generic mechanism separate from this machine's hardware facts.

### Reusable NixOS module

Replace `modules/nixos/virtualisation/libvirt.nix` with a disabled-by-default
module such as `workstation.virtualisation`. It should own:

- hardened libvirt service defaults;
- typed NAT and isolated network declarations;
- typed domain declarations for x86 KVM and trusted ARM TCG guests;
- safe create-once disk initialization;
- persistent domain/network reconciliation;
- `virt-manager`, `virt-viewer`, `virsh`, and a small `vm` CLI;
- XML generation and validation checks;
- assertions around acceleration, storage paths, autostart, TPM, and VFIO;
- backup manifests that enumerate disk, NVRAM, TPM, and domain identity;
- no physical PCI IDs, usernames, fixed memory sizes, or private subnets as
  module-wide assumptions.

A useful option shape is:

```nix
workstation.virtualisation = {
  enable = true;
  storage.root = "/var/lib/libvirt/images";

  networks = {
    management = { mode = "isolated"; subnet = "..."; };
    egress = { mode = "nat"; subnet = "..."; };
  };

  guests.<name> = {
    architecture = "x86_64"; # or "aarch64"
    accelerator = "kvm";     # or "tcg"
    trust = "trusted";
    vcpus = 4;
    memoryMiB = 8192;
    autostart = false;
    exclusiveGroup = "heavy";
    networks = [ "management" "egress" ];
    disk = {
      path = "/var/lib/libvirt/images/<name>/disk.qcow2";
      format = "qcow2";
      initialSizeGiB = 80;
    };
    tpm.enable = false;
    secureBoot = false;
    vfio.devices = [ ];
  };
};
```

The interface should reject:

- `aarch64` plus `kvm` on this `x86_64` host;
- untrusted TCG guests;
- disk, NVRAM, or TPM paths in `/nix/store`, `/tmp`, or a relative path;
- VFIO on an autostarting guest;
- duplicate disk paths or PCI addresses;
- autostart declarations whose combined memory violates the configured host
  reserve;
- a passthrough guest without an explicit recovery/profile guard;
- broad trusted firewall interfaces;
- implicit disk deletion or shrink when a declaration disappears or changes.

Some facts need runtime checks because Nix evaluation cannot prove them:

- `/dev/kvm` and the requested QEMU machine/firmware exist;
- the selected PCI functions still form complete, isolated IOMMU groups;
- no selected device is mounted or owns the active host display;
- the storage directory has the intended NOCOW attribute before image creation;
- the libvirt network subnets do not overlap current host routes;
- domain XML validates against the installed libvirt schema.

Fail activation before mutating device ownership when a preflight check fails.
Reconciliation may define or update an inactive domain and create a missing
disk, but it must never force-stop a running guest, delete an undeclared disk,
or silently resize mutable storage. NixVirt offers declarative libvirt objects,
but its own README warns that `master` is frequently broken and its current
`virtdeclare` behavior can deactivate and reactivate an active object when its
definition changes. If it is adopted, pin a reviewed release and wrap that
behavior. For two domains, a small in-repository reconciler with safer
semantics is easier to audit. See the
[NixVirt project documentation](https://github.com/AshleyYakeley/NixVirt).

Use the stable emulator and firmware symlinks created by the pinned NixOS
libvirt module rather than embedding generation-specific Nix store paths in
persistent XML. The module exposes QEMU firmware under `/run/libvirt` and
intentionally avoids restarting libvirt and guests on every NixOS switch. See
the [pinned module implementation](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/nixos/modules/virtualisation/libvirtd.nix#L406-L654).

Add evaluation tests for every rejected combination, golden tests for generated
network and domain XML, `virt-xml-validate` checks against the pinned libvirt,
and unit tests for runtime route, storage, and IOMMU-group parsing. Hardware
passthrough still needs the staged test on `desktop`; a synthetic NixOS VM test
cannot prove physical group isolation or GPU reset behavior.

### Desktop-local policy

Put the following in a host-local module under
`hosts/nixos/desktop/local/`:

- actual subnets and DHCP reservations;
- disk locations and initial sizes;
- Ryzen resource budgets;
- RTX and audio PCI IDs/addresses;
- the iGPU-only host graphics profile;
- the boot specialization that binds group 12 to VFIO;
- Windows installation media paths;
- SSH aliases and public host keys;
- recovery assertions and operator-facing warnings.

That follows the repository's existing split: reusable modules own mechanism,
and local host files own hardware and personal policy.

### Mac-local policy

Keep Determinate's native Linux builder enabled in the shared Darwin module.
Do not add a second Mac VM manager, VM-specific key activation, or guest proxy
aliases for architecture builds. The existing VMware Windows helper remains a
separate machine-specific concern.

## Operator UX

Provide one narrow command interface instead of requiring routine XML editing:

```text
vm list
vm doctor [name]
vm start <name>
vm stop <name>
vm console <name>
vm ip <name>
vm ssh <name>
vm backup <name>
vm status <name>
```

`vm doctor windows` should report the current boot profile, GPU drivers,
complete IOMMU group, storage/NOCOW state, firmware, TPM state, network, and
whether starting is safe. `vm start` should use an allowlisted name and a
root-owned unit; it should not accept arbitrary libvirt XML or device paths.
It should refuse to start a second running member of the same
`exclusiveGroup`, which keeps the 30 GiB host out of memory overcommit during
normal operation.
`vm ssh` should call the same concrete SSH alias Codex uses. Keep `virt-manager`
for installation and occasional hardware inspection. Do not enable Cockpit or
the Incus UI for a dashboard alone; each would add a resident network service
and another authorization path.

The useful Codex boundary for desktop guests is the SSH alias, not a shared
host filesystem. Keep VM power operations separately elevated. ARM package
builds on the Mac go through Nix and the existing native builder rather than a
guest SSH alias. This keeps an unattended agent from gaining general libvirt or
Incus administration.

## Rollout and acceptance gates

### Stage 1: safe libvirt baseline

1. Replace the unused stub with the hardened, disabled-by-default module.
2. Evaluate and boot it with no guests, no VFIO, and no bridge trusted by the
   firewall.
3. Run `virt-host-validate qemu` and record the effective QEMU user, sandbox,
   cgroup, and security driver.
4. Create a disposable x86-64 Linux KVM guest, verify NAT, isolation, shutdown,
   restore, and the Codex SSH alias, then delete only its explicitly disposable
   disk.

Gate: the daily user is not in `libvirtd`; QEMU is non-root; no VM management
port is listening on the LAN; host services remain reachable if the guest
misbehaves.

### Stage 2: ARM execution paths

1. Add the trusted AArch64 TCG smoke-test domain using the full `pkgs.qemu`.
2. Confirm Determinate's native Linux builder is enabled on the M4.
3. Build the same representative `aarch64-linux` output under desktop TCG and
   the M4 builder.

Gate: TCG is never presented as an untrusted security boundary; normal ARM
work chooses the native M4 builder.

### Stage 3: Windows without VFIO

1. Create Windows storage in the NOCOW directory.
2. Install with Q35, UEFI, swtpm 2.0, Secure Boot capability, VirtIO, virtual
   display, and no passed-through device.
3. Verify guest-agent shutdown, backup/restore, BitLocker recovery, SSH or RDP
   access, and host resource headroom.

Gate: the VM survives restore with its NVRAM and TPM state; the host remains
responsive under the selected memory and CPU allocation.

### Stage 4: VFIO profile

1. Prove an iGPU-only NixOS generation and physical recovery path.
2. Add the `windows-vfio` boot specialization for both group-12 functions.
3. Verify the preflight guard refuses Windows in the wrong profile.
4. Test physical RTX output, audio, repeated resets, host shutdown, and rollback.

Gate: no ACS override, no shared IOMMU group, no automatic guest start, and a
known-good non-VFIO boot generation remains selectable.

### Stage 5: tune only from measurements

Measure guest CPU, storage latency, host input latency, audio, Codex build time,
memory pressure, and reset reliability. Add CPU pinning, I/O threads,
hugepages, shared-display tools, or a dedicated VM SSD only when a measured
bottleneck justifies their maintenance and recovery cost.

## Final decision

Use NixOS plus libvirt/KVM/QEMU on the desktop. Use the M4 Mac host for
`aarch64-darwin` and its existing Determinate native Linux builder for
`aarch64-linux`. Add an optional boot-time libvirt/VFIO profile for Windows
after the AMD iGPU is proven as the host display. Keep Incus out until there is
a real Linux system-container fleet, and reserve Proxmox for a future dedicated
hypervisor machine.
