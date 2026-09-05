# Declarative Windows 11 VM provisioning

Research date: 2026-09-03

## Decision

Build the Windows guest from a public, versioned recipe, but keep the deployed
workload as persistent state. The useful guarantee is that the VM can be
rebuilt and audited. A Windows image assembled from current updates will not be
bit-for-bit reproducible.

The deployed workstation intentionally overrides this paper's safer UAC and
two-account recommendation. Its fixed requirement is one persistent,
autologged-on local Administrator with UAC disabled and live private access.
The implementation records that choice explicitly and moves the remaining
controls to libvirt, the host firewall, fixed-path provisioning, and strict
management access. The discarded-lab model is not the primary runtime.

The implemented first version also chooses the direct answer-ISO lifecycle
described below instead of adding Packer and a generalized base-image layer
for one persistent guest. `docs/workstation-virtualization.md` is the
authoritative deployed design and operating procedure; the alternatives in
this document remain a research record.

Use these layers:

```text
Public nix-conf repository
  Windows edition and ISO SHA-256
  pinned Packer QEMU plugin
  Autounattend template without passwords or product keys
  pinned VirtIO media
  supported Windows policies and package declarations
  declarative libvirt domain XML
              |
              v
Root-only build inputs under /run
  temporary bootstrap password
  temporary answer-file ISO
              |
              v
Versioned generalized base qcow2
              |
              v
Persistent windows-dev disk, TPM state, UEFI variables, UUID and MAC
              |
              v
Private provisioning overlay
  vendor applications, private identifiers, credentials, autologon secret,
  application tasks, settings and development integration
```

Keep libvirt as the runtime manager. Packer is an image compiler, not a second
always-running hypervisor. The official QEMU builder creates KVM images from an
ISO and supports checksums, UEFI, virtual TPM, qcow2, WinRM provisioning and
headless builds. Pin the plugin version. Do not run Packer against the deployed
disk or its TPM state. See the [official QEMU builder](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu),
[Windows Autounattend guide](https://developer.hashicorp.com/packer/guides/automatic-operating-system-installs/autounattend_windows),
and [plugin installation guidance](https://developer.hashicorp.com/packer/docs/plugins/install).

For the first implementation, Packer is optional. A generated answer-file CD,
declarative libvirt XML and a clean installation into the final disk provide
most of the value with fewer moving parts. Add Packer after clean rebuilds work
and base installation time becomes a real cost.

## What can be declarative

The public repository can own:

- Windows edition, language, disk layout and image index;
- the expected SHA-256 of the manually acquired Microsoft ISO;
- four vCPUs, 8 GiB RAM, Q35, UEFI, TPM 2.0, VirtIO SCSI and networking,
  balloon reporting, and a virtual display;
- stable domain UUID, SMBIOS UUID, MAC addresses and device addresses;
- an Autounattend template for Windows Setup;
- the VirtIO media version;
- baseline PowerShell, WinGet Configuration and DSC documents;
- generic maintenance-task XML without private principals or paths;
- tests for activation, drivers, updates, UAC, Defender, Firewall, autologon,
  scheduled tasks and guest-agent health.

Libvirt domain XML is a good declarative boundary. `virsh define` registers a
persistent domain without starting it, and `--validate` checks the document.
The XML describes firmware, CPU, memory, storage, networking, TPM and display.
See the [libvirt domain XML reference](https://libvirt.org/formatdomain.html)
and [virsh reference](https://www.libvirt.org/manpages/virsh.html).

The host module should reconcile only an inactive domain. It must not replace a
running guest or delete its disks. Keep mutable objects outside the Nix store:

```text
/var/lib/libvirt/images/windows-dev/system.qcow2
/var/lib/libvirt/qemu/nvram/windows-dev_VARS.fd
/var/lib/libvirt/swtpm/windows-dev/
```

The UUID, MAC, TPM state, UEFI variables and system disk should survive a NixOS
switch. Changing them can affect Windows activation, stored credentials and
vendor machine identity.

## Acquiring Windows media

The selected production guest uses Windows 11 Pro from Microsoft's Windows 11
25H2 multi-edition x64 ISO. Microsoft publishes the ISO and its language-level
SHA-256 on the public Windows 11 download page, but the generated artifact URL
expires after 24 hours. The durable recipe therefore pins the release,
filename, image name, source page, and hash, while retaining the bytes as a
private local artifact.

1. On Microsoft's [Windows 11 download page](https://www.microsoft.com/en-us/software-download/windows11),
   select the multi-edition x64 ISO and English (United States).
2. Download `Win11_25H2_English_x64_v2.iso` and compare it with Microsoft's
   published SHA-256
   `768984706B909479417B2368438909440F2967FF05C6A9195ED2667254E465E3`.
3. Stage it as
   `/var/lib/libvirt/boot/Win11_25H2_English_x64_v2.iso`.
4. Make the installer calculate SHA-256 and refuse a mismatch before QEMU
   starts. Inspect `install.wim` or `install.esd` and also refuse media without
   the declared `Windows 11 Pro` image name.

Do not commit or redistribute the ISO or paste its expiring signed URL into
Nix. Back up the verified file to a private artifact location if long-term
rebuilds matter. The recipe remains declarative even though media acquisition
is a manual input. The public
[Enterprise evaluation](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise)
is suitable only for a disposable compatibility trial. Windows client
Evaluation media cannot be turned into the released edition by adding a key;
production LTSC must instead come from an authenticated
[volume-license download](https://learn.microsoft.com/en-us/microsoft-365/commerce/licenses/download-vl-products).

The complete channel comparison and the reason no permanent public production
ISO URL can be used are in `docs/windows-iso-source-research.md`.

Every installed copy needs a valid license and activation. The owner has
confirmed that the key is available and activation will occur later in the
guest, so neither the key nor an activation command belongs in the public
answer file. Microsoft's
[Windows 11 licensing guide](https://www.microsoft.com/licensing/docs/documents/download/Windows_11_Commercial_Licensing_Guide.pdf)
describes activation and virtual-desktop rights.

## Unattended installation and VirtIO

Place `Autounattend.xml` at the root of a small build-only ISO. Windows Setup
searches removable media for that filename. The answer file can declare locale,
edition, GPT partitions, OOBE behavior, a bootstrap account and one bootstrap
command. Microsoft documents this in
[Automate Windows Setup](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/automate-windows-setup?view=windows-11)
and [Answer files](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/update-windows-settings-and-scripts-create-your-own-answer-file-sxs?view=windows-11).

Attach the Windows ISO, answer-file ISO and pinned VirtIO ISO during the build.
Windows Setup needs the VirtIO SCSI driver before it can see a VirtIO-backed
system disk. Use `Microsoft-Windows-PnpCustomizationsWinPE` to point Setup at
the signed driver directory. Install the network, balloon, guest-agent and
display components after Windows boots. Microsoft documents the driver path in
[Add a device driver path](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/wsim/add-a-device-driver-path-to-an-answer-file),
and the upstream project publishes the
[VirtIO Windows driver media and signing notes](https://github.com/virtio-win/virtio-win-pkg-scripts).

Do not rely on several `FirstLogonCommands` running in sequence. Microsoft says
current `SynchronousCommand` entries start concurrently despite their order
values. Use one first-logon command that invokes a bootstrap script. Let that
script handle order, retries and logs. See the
[FirstLogonCommands order documentation](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-firstlogoncommands-synchronouscommand-order).

Packer can use WinRM for provisioning. Its simple HTTP and Basic authentication
examples are not a secure final configuration. Limit WinRM to the isolated
management network, use it only during bootstrap, and close or harden the
listener at the end. See the [Packer WinRM communicator](https://developer.hashicorp.com/packer/docs/communicators/winrm).

If Packer produces a reusable base, finish with:

```powershell
sysprep.exe /generalize /oobe /shutdown /mode:vm
```

Microsoft requires generalization before copying a Windows installation. It
removes machine-specific state and prepares the `specialize` pass for the next
boot. The `/mode:vm` option applies when the image returns to the same virtual
hardware. See [Sysprep generalization](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep--generalize--a-windows-installation?view=windows-11).

Keep the versioned generalized base immutable, then create a standalone deployed
disk from it. A qcow2 backing overlay saves space but makes the live VM depend
on the exact base pathname and contents. Libvirt records that dependency as a
backing chain. See [Disk image chains](https://libvirt.org/kbase/backing_chains.html).
For one important long-lived VM, a standalone disk is less fragile.

## Baseline configuration

Split configuration into three stages.

### Setup stage

Autounattend should do only what Windows Setup owns:

- select the image and create GPT partitions;
- set locale and a generic computer name;
- create a temporary bootstrap administrator;
- automate supported OOBE pages;
- locate the VirtIO storage driver;
- invoke one bootstrap script.

Do not put a permanent password, product key, private credential or Git token
in the public answer file. Windows SIM's "Hide Sensitive Data" option is
obfuscation, not encryption. Microsoft says to treat answer files as sensitive
data. See
[Hide sensitive data in an answer file](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/wsim/hide-sensitive-data-in-an-answer-file).

Render the final answer file under `/run` from a public template plus a fresh
temporary password. Build the seed ISO there, restrict it to the image-builder
service, detach it after provisioning and remove the temporary files. Rotate or
delete the bootstrap account before accepting the image. A Packer variable
marked `sensitive` redacts normal output but is not secret storage. See
[Packer input variables](https://developer.hashicorp.com/packer/docs/templates/hcl_templates/blocks/variable).

### Public operating-system baseline

Use one reviewed PowerShell bootstrap to install enough tooling for a
declarative configuration, then apply WinGet Configuration or DSC. Microsoft's
[WinGet Configuration](https://learn.microsoft.com/en-us/windows/package-manager/configuration/)
uses YAML, package declarations and DSC resources to bring a machine to a
declared state. Its `validate`, `test` and `configure` operations provide a
clearer acceptance boundary than an opaque debloat script. Microsoft warns that
an elevated configuration can make administrative changes with few prompts, so
pin and review every package and DSC module. See
[checking a WinGet Configuration](https://learn.microsoft.com/en-us/windows/package-manager/configuration/check).

The baseline should install tools by exact package ID, configure a management
channel only on the isolated network, preserve Defender and Firewall, retain
Windows Update, set maintenance hours, disable sleep and hibernation, and remove
only measured startup costs. Use DSC or explicit policy resources for settings
that have supported Windows interfaces. DSC 3 configuration documents provide
`get`, `test` and `set`; DSC 3 runs on demand rather than keeping a resident
configuration service. See the
[DSC overview](https://learn.microsoft.com/en-us/powershell/dsc/overview?view=dsc-3.0)
and [`dsc config`](https://learn.microsoft.com/en-us/powershell/dsc/reference/cli/config/?view=dsc-3.0).

Avoid generic debloat scripts. Do not remove or disable Defender, Firewall,
Windows Update, Event Log, Task Scheduler, WMI, PowerShell, .NET, WebView, App
Installer or guest-agent services. Remove a provisioned app only from a short,
reviewed allowlist through DISM or its supported package interface. Microsoft's
[offline package servicing documentation](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-or-remove-packages-offline-using-dism?view=windows-11)
shows why package order and dependencies matter.

Reasonable public optimizations are conservative:

- use VirtIO storage and network drivers;
- disable sleep and hibernation while allowing the virtual display to blank;
- select only the development packages actually used;
- disable startup applications after measuring their impact;
- choose the "best performance" visual-effects setting for a mostly unattended
  GUI guest;
- set optional diagnostic data to the lowest supported level for the edition;
- keep a system-managed page file and automatic security updates.

Microsoft documents [startup application impact](https://support.microsoft.com/en-US/Windows/Experience/Startup-Boot/configure-startup-applications-in-windows),
[visual performance settings](https://support.microsoft.com/en-au/windows/tips-to-improve-pc-performance-in-windows-b3b3ef5b-5953-fb6a-2528-4bbed82fba96),
and [diagnostic data policy](https://learn.microsoft.com/en-us/windows/privacy/configure-windows-diagnostic-data-in-your-organization).

### Private workload overlay

Keep all workload-specific knowledge out of this public repository:

- vendor and organization names;
- private identifiers, API keys, licenses and passwords;
- application workspaces and profiles;
- private binaries, source code and integration configuration;
- autologon credentials;
- application-specific scheduled tasks and executable paths;
- certificates, SSH private keys and recovery tokens.

Apply this overlay only to the final persistent guest. A private repository can
hold non-secret automation and encrypted payloads. Actual secrets should come
from the existing age-encrypted system or another secret manager and decrypt
into a root-only runtime directory. Transfer them over the isolated management
network or a one-use seed disk. Detach and destroy the seed disk after import.
Never put secret values in a Nix derivation, Packer default, command line, build
log or public Git history.

The existing workload-specific virtualization research note should not be
staged or committed if this repository will be public. Its filename and content
disclose the private workload even without credentials.

## Administrator rights and UAC

Windows has no direct equivalent of "full sudo without UAC." Membership in the
local Administrators group and UAC are separate choices. With UAC enabled, an
administrator signs in with a filtered standard token and receives the full
token only for an elevated process. With UAC disabled, every process started by
that user gets the full administrator token. Microsoft calls UAC a key Windows
security control because it limits what malicious code can do through an
administrator account. See
[How UAC works](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/how-it-works).

Disabling UAC is a bad default for a network-connected GUI VM that downloads
updates and holds private credentials. A bug in an application, plugin or web
component would gain full control of Windows without an elevation boundary.
Microsoft documents that disabling Admin Approval Mode gives programs the
signed-in user's full token and removes related UAC protections. Its narrow
exception is a server where administrators sign in solely to perform system
administration. A persistent GUI workload does not meet that condition. See
[effects of disabling UAC](https://learn.microsoft.com/en-us/troubleshoot/windows-server/windows-security/disable-user-account-control).

Use this account model:

| Account | Membership | Logon | Use |
| --- | --- | --- | --- |
| `runtime` | Standard user unless testing proves otherwise | Automatic console logon | Private GUI applications and their agent |
| `devadmin` | Local Administrators | Manual or management channel | Debugging, installs, updates and task registration |
| Task principals | SYSTEM or a named account | No normal desktop | Small, fixed machine operations |

Keep UAC enabled. Register tasks from an elevated provisioning step. Task
Scheduler supports the `HIGHEST` run level and can launch a named elevated
action without a prompt on every trigger. See
[schtasks](https://learn.microsoft.com/en-us/windows/win32/taskschd/schtasks).

Use fixed, reviewed task definitions for installation, maintenance, diagnostics
and graceful shutdown. If an exact GUI application proves that it must run
elevated, launch only that fixed executable at console logon using a
highest-privilege task tied to the interactive user. Do not make the whole
autologon desktop unrestricted.

Every elevated task should call an administrator-owned script with fixed
arguments. Do not create an elevated task that accepts arbitrary commands or
points to a directory writable by the runtime user. That would bypass UAC just
as thoroughly as turning it off.

PowerShell Just Enough Administration is useful if Codex needs remote
administration without an unrestricted administrator shell. A JEA endpoint can
allow only named cmdlets and functions, use temporary privileged virtual
accounts, and retain transcripts. See the
[JEA overview](https://learn.microsoft.com/en-us/powershell/scripting/security/remoting/jea/overview?view=powershell-7.6).

If unrestricted experiments are necessary, create a separate disposable
`windows-lab` clone. It can use an administrator with prompt-free elevation,
but it must not contain private credentials, connect to production endpoints or
share the persistent VM's private disk. Rebuild it from the public base after
risky experiments. Do not weaken the persistent VM for development convenience.

## Autologon and GUI startup

Autologon is compatible with this design because GUI applications need an
interactive console session. Configure it after the public image build using a
private secret. Microsoft's Sysinternals Autologon stores the password as an
LSA secret instead of a clear-text Winlogon value. Microsoft also warns that a
local administrator can retrieve and decrypt it. See
[Sysinternals Autologon](https://learn.microsoft.com/en-us/sysinternals/downloads/autologon).

Use a unique local password with no value outside this VM. Never reuse an
online identity, email, host or application password. Treat every local
administrator as able to become the autologon user.

The startup sequence should be:

1. Windows completes boot and automatic console logon.
2. An at-logon task starts the private coordinator after network readiness
   checks.
3. The coordinator starts only the required GUI applications in that same
   interactive session.
4. Elevated maintenance tasks stay separate from the daily desktop.
5. Health checks verify the console session, processes, agent heartbeat and
   update or reboot status before external actions are enabled.

Keep Windows Update enabled and set maintenance hours so a restart does not
interrupt the workload. Microsoft's policy reference supports active-hour and
restart deadline controls. See
[Windows update policies](https://learn.microsoft.com/en-us/windows/configuration/wcd/wcd-policies#update).

## Image lifecycle

Replace the public base image when the Windows feature release, source ISO,
VirtIO version or public policy baseline changes materially. Maintain security
updates, vendor application state and private configuration in the deployed
guest.

Do not automatically replace the deployed disk. Build and boot a
`windows-candidate`, apply the private overlay, run native acceptance tests,
then perform a deliberate cutover. Keep the previous disk for a short rollback
period. Back up the system disk, TPM state, UEFI variables and private recovery
material together while the guest is shut down or through a guest-coordinated
backup. A public base-image recipe cannot restore private application state.

## Proposed public repository layout

```text
windows/
  README.md
  packer/
    windows-11.pkr.hcl
    versions.pkr.hcl
  answer/
    Autounattend.xml.in
  bootstrap/
    Bootstrap.ps1
    Test-Baseline.ps1
  configuration/
    baseline.dsc.winget
  tasks/
    maintenance.xml.in
  libvirt/
    windows-dev-domain.nix
```

Add a narrow host-side lifecycle:

```text
vm image verify windows-dev
vm image build windows-dev
vm image inspect windows-dev
vm install windows-dev
vm test windows-dev
```

`build` should use a dedicated image-builder service with access only to the
staged ISO, VirtIO media, KVM and its output directory. `install` should refuse
to overwrite an existing disk. A separate explicit promotion command can
replace a stopped candidate after verifying a backup. None of these commands
should accept arbitrary QEMU arguments, libvirt XML or shell fragments.

## Recommended rollout

1. Choose and license Windows 11 Pro or Enterprise.
2. Keep only the Windows domain in the normal libvirt guest inventory.
3. Add declarative domain XML, with autostart off during workstation use.
4. Add a public Autounattend template and runtime-generated seed ISO. Perform a
   clean installation without Packer first.
5. Install pinned VirtIO drivers, the guest agent and public baseline. Run the
   baseline tests.
6. Keep UAC enabled. Create `runtime` and `devadmin`; test private applications
   as `runtime` before granting more rights.
7. Apply the private overlay outside the public image build.
8. Configure Sysinternals Autologon and a fixed private at-logon task.
9. Test cold boot, power loss, update reboot, console reconnect, expired
   credentials, lost network and recovery from an ambiguous external action.
10. Add Packer and a generalized base after the single-install path is reliable.

This design provides a reviewable rebuild path without pretending a long-lived
Windows workload is immutable. It gives the development account administrator
membership while preserving UAC around the network-facing autologon session.
