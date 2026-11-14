# Windows VM quality review research

Reviewed: 2026-09-24. Scope: the declared Windows 11 Pro libvirt guest, its
unattended bootstrap and verification templates, desktop policy, and
`workstation-virtualization.md` at `9ec1fafddf29c17aacf48fa37d0112a68af89f99`.

## Answer

The virtual hardware has a sound Windows 11 baseline. It exceeds Microsoft's
VM minimums and uses a Q35 machine, UEFI firmware with Secure Boot, a persistent
TPM 2.0 emulator, 4 vCPUs, 8 GiB memory, and a 128 GiB disk. It should remain
on that path.

There are two release blockers in the unattended path. The desktop selects
`EnableLUA=0` before OOBE, while Microsoft says `FirstLogonCommands` do not run
when UAC is disabled. That is the only mechanism that starts `Bootstrap.ps1`.
The generated Windows OpenSSH configuration also includes
`KbdInteractiveAuthentication`, which Microsoft lists among options unavailable
in the Windows OpenSSH build. The current check only parses PowerShell and XML.
It cannot prove that Windows Setup starts provisioning, that `sshd` accepts the
generated configuration, or that final VirtIO boot works.

Microsoft offers the current consumer multi-edition ISO through an interactive
page that says it is suitable for a virtual machine. Its generated links expire
after 24 hours. Make acquisition a controlled runtime operation, not a
fixed-output Nix fetch. It must obtain the current official link, verify the
SHA-256 Microsoft publishes for the exact locale, verify the WIM image label,
and save a local manifest. A static derivation cannot safely represent either a
changing "latest" ISO or a signed URL that expires a day after creation.

## Native installation follow-up

Verified on a native x86-64 Linux desktop on 2026-10-08. The declared production
ISO passed its pinned SHA-256 and Windows 11 Pro image checks. Unattended setup
completed, the public baseline passed, and finalization cold-booted the system
disk through VirtIO SCSI. Setup media, the temporary driver-prime disk, and
host-side installation credentials were removed. The guest reported enabled
Secure Boot, a ready TPM, and an automatically restored interactive shell.
Key-only SSH worked from both configured clients after pinning the host key
through the trusted guest-agent channel. Licensing is outside this deployment.

Native installation exposed three additional provisioning failures that static
syntax checks did not catch:

- `systemd-inhibit` removed the readiness child's `NOTIFY_SOCKET`. Pass that
  socket explicitly to the child after acquiring the sleep inhibitor. The
  [native regression probe](../../tests/systemd/check-libvirt-sleep-inhibitor.sh)
  checks readiness and lock release.
- `swtpm_localca` needed its packaged tmpfiles rule and the `tss` system account
  to create its certificate authority state. Register both without enabling
  physical TPM access.
- Administrator-generated OpenSSH host keys had an owner rejected by the
  SYSTEM service. Replace SSH directory and private-file DACLs, assign
  Administrators ownership, and restrict access to SYSTEM and Administrators.
  The service then started and accepted pinned-key SSH. This follows the
  upstream [Windows OpenSSH file protection guidance](https://github.com/PowerShell/Win32-OpenSSH/wiki/Security-protection-of-various-files-in-Win32-OpenSSH).

Cold boot also exposed an unconfigured `ACPI\QEMU0002` device. Installing the
signed `fwcfg` driver from the same pinned VirtIO media cleared configuration
error 28. Provisioning now includes that driver, and the baseline rejects
nonzero PnP configuration errors. The fresh baseline checks SSH permissions
in addition to the existing policy. The host doctor and guest health checks
passed. Applicable automatic software updates installed successfully, including
the cumulative security update, followed by an orderly reboot. A second round
updated the Defender antimalware platform; the final update scan returned zero
applicable updates. Fresh baseline validation passed after the reboot, the
interactive shell returned automatically, and the health check reported no
pending reboot or device error. A saved provisioning `PASS` alone would not
establish those results.

Targeted host integration is persistent and uses the generated Nix launcher.
Its native sleep-lock probe passes, and the running guest holds one sleep lock.
The declarative source fixes have independent review. Generated artifact
validation passed, along with 10 focused control tests and four subtests.
The complete desktop configuration has not been activated as part of this
installation.

No independent backup destination is declared. Keep the disk, inactive domain
XML, NVRAM, and persistent TPM state together when adding recovery coverage,
as described in the [backup runbook](../operations/workstation-virtualization.md#backups-and-recovery).

## Findings and sources

### VM hardware and host policy

**Source guidance.** Microsoft supports Windows 11 in a VM with a Generation 2
configuration, at least 64 GB storage, 4 GB memory, two vCPUs, Secure Boot
capability, and a virtual TPM. The host CPU must also meet the Windows 11 CPU
requirement. [Windows 11 requirements](https://learn.microsoft.com/en-us/windows/whats-new/windows-11-requirements)
also says a Generation 1 VM cannot be upgraded in place.

**Repository observation.** The domain template in
[`windows-vm.nix`](../../modules/nixos/virtualisation/windows-vm.nix) declares
Q35, a Secure Boot OVMF loader and Microsoft variable template, persistent TPM
2.0 state, four static vCPUs, 8192 MiB memory, and a 128 GiB disk. The desktop
configuration selects matching values in
[`security/virtualization.nix`](../../hosts/nixos/desktop/local/security/virtualization.nix).
The module validates both generated domain documents with `virt-xml-validate`.

**Inference and next step.** Keep the stable UUID, generation ID, disk serial,
NVRAM, and TPM state with any restored disk. Add one activation-time or
operator-run acceptance test on the desktop that starts the installed domain
and records firmware, TPM, Secure Boot, and guest-agent health. XML validation
does not establish that the installed QEMU, firmware, and host kernel can boot
the guest. The evaluated package set currently reports QEMU 11.1.1, libvirt
12.7.0, virtio-win 0.1.302-1, and OVMF 202608. The configured
`pc-q35-10.2` compatibility machine should be checked with the installed QEMU
domain capabilities before changing that pin.

### Unattended bootstrap cannot run with the selected UAC policy

**Source guidance.** Microsoft documents that `FirstLogonCommands` run with
elevated access for an administrator's first logon, but do not run when UAC is
disabled. It also says these commands no longer wait for one another, despite
the `SynchronousCommand` name. See
[FirstLogonCommands](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-firstlogoncommands)
and [its ordering rule](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-firstlogoncommands-synchronouscommand-order).
Microsoft describes `EnableLUA=0` as disabling Admin Approval Mode and lists
enabled UAC as the default in [UAC settings and configuration](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/settings-and-configuration).

**Repository observation.** `Autounattend.xml.in` writes `EnableLUA` during
the `specialize` pass. The desktop sets `administrator.disableUac = true`, so
the value is zero before the `oobeSystem` pass. The same answer file then uses
one `FirstLogonCommands` entry to locate and start `Bootstrap.ps1`.

**Inference and next step.** Treat this as a blocker. Keep UAC enabled until
the bootstrap has started, then apply the accepted runtime UAC policy inside a
tested bootstrap phase followed by the required restart. A more robust choice
is a Setup-phase mechanism that runs as SYSTEM, with an explicit completion
signal and retry path. Do not rely on `Order` if more first-logon commands are
introduced. Add a real installation acceptance test that requires the guest
agent's signed baseline result and checks the bootstrap log after the first
OOBE boot.

### Windows OpenSSH template uses an unavailable setting

**Source guidance.** Microsoft says Windows OpenSSH reads
`%ProgramData%\\ssh\\sshd_config`, requires a service restart after a change,
and uses `%ProgramData%\\ssh\\administrators_authorized_keys` for administrator
accounts. Its Windows-specific reference lists
`KbdInteractiveAuthentication` as unavailable. See
[OpenSSH Server Configuration for Windows](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-server-configuration).

**Repository observation.** `Bootstrap.ps1.in` writes
`KbdInteractiveAuthentication no` into `sshd_config` and restarts `sshd`.
`Test-Baseline.ps1.in` only verifies that this text appears, alongside
`PasswordAuthentication no`. The ACL that the template applies to
`administrators_authorized_keys` matches Microsoft's documented SYSTEM and
Administrators ownership guidance.

**Inference and next step.** Remove the unavailable directive and its
text-only assertion. After rendering configuration, run `sshd -t`, restart the
service, and test an Ed25519 public-key connection from the management host.
The existing Windows Firewall rule still supplies the needed source-address
restriction. Add its remote address and the effective `AllowUsers` result to a
fresh guest verification, rather than treating a registry or text check as a
network test.

### Guest agent and VirtIO devices need a narrower operational check

**Source guidance.** QEMU recommends VirtIO device models when a guest driver
is available. [QEMU's VirtIO documentation](https://www.qemu.org/docs/master/system/devices/virtio/index.html)
describes them as paravirtualized, efficient device models. The Windows QEMU
guest agent requires a working VirtIO serial driver and the
`org.qemu.guest_agent.0` channel, according to the
[virtio-win guest-agent guide](https://virtio-win.github.io/Knowledge-Base/Qemu-ga-win.html).
QEMU documents guest-agent file access, freeze, suspend, time, and password
operations, and says an agent permits all RPCs unless an allow or block list is
configured. See [QEMU Guest Agent](https://www.qemu.org/docs/master/interop/qemu-ga.html).

**Repository observation.** The template installs signed VirtIO drivers,
creates the required channel, and uses `guest-file-open`, `guest-file-read`,
and `guest-file-close` to return only status, logs, and the SSH host key through
the fixed privileged helper. The baseline verifies `vioscsi` and that `qemu-ga`
is running, then finalization cold-boots the runtime VirtIO SCSI definition.

**Inference and next step.** Configure the Windows guest agent with the
smallest RPC allowlist that supports the fixed helper and graceful shutdown, or
document why a broader set is necessary. Verify the installed agent's supported
RPC names first, since QEMU versions differ. Add a test after the runtime
cold boot that checks the boot disk driver, both NICs, guest-agent channel, and
only the intended host-to-guest RPCs. The present checks establish template
syntax, not those runtime facts.

### Servicing and documentation are current but need a dated review point

**Source guidance.** Windows 11 Pro 25H2 remains supported through 2027-10-13,
and Microsoft gives Pro a 24-month servicing period per annual release. See
[Windows 11 Home and Pro lifecycle](https://learn.microsoft.com/lifecycle/products/windows-11-home-and-pro)
and the [Windows lifecycle FAQ](https://learn.microsoft.com/en-us/lifecycle/faq/windows).
Microsoft's update policy documents the paired `ProductVersion` and
`TargetReleaseVersion` settings used to stay on a declared supported feature
release. See [Update Policy CSP](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-update).

**Repository observation.** The desktop pins the 25H2 ISO identity and target
release policy. The runbook correctly says the production ISO URL expires and
the retained verified ISO is needed for a reproducible reinstall. It identifies
the absent guest disk and ISO in its 2026-09-10 review, but its verification
section is limited to generated artifacts.

**Inference and next step.** Preserve the 25H2 pin while it is supported, then
review the ISO hash, WIM image label, VirtIO media, and target release policy
before 2027-10-13. Extend the runbook's verification section with first install,
cold runtime boot, Windows Update reboot, guest-agent recovery, and restore
tests. Windows 11 Pro for personal use also has an initial Internet and
Microsoft-account requirement in Microsoft's consumer specifications. Whether
this unattended, locally administered Pro installation has a licensing route
that permits its OOBE choice needs an owner decision rather than a technical
assumption.

### Automated acquisition of the latest production ISO

**Source guidance.** Microsoft's [Windows 11 download page](https://www.microsoft.com/en-us/software-download/windows11)
offers the multi-edition x64 ISO for installation media and virtual machines.
It says generated download links are valid for 24 hours and publishes a
SHA-256 verification value for each language image. The ISO is multi-edition,
with the product key unlocking the applicable edition. The page sends
Enterprise downloads through authenticated Microsoft 365 or Visual Studio
subscription channels. [Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)
identifies 25H2 as the current general-availability release at retrieval.
Microsoft's download page says a license is required to install Windows 11.
Downloading an ISO does not grant a Pro license.

**Repository observation.** The desktop pins a 25H2 English x64 v2 filename,
hash, image label, and stable Microsoft download page. `windows-vm stage-iso`
requires an operator-supplied file. The runbook correctly notes that the actual
Microsoft URL expires after 24 hours. Review of the public page found no
documented unattended Linux API for selecting the consumer ISO, generating its
short-lived URL, and retrieving the matching hash.

**Inference and recommended design.** Replace operator staging with a
root-owned `windows-vm refresh-media` runtime operation, enabled by an explicit
Nix policy such as `installation.acquire.enable = true`. It should declare the
consumer channel, x64 architecture, locale, and either a reviewed release such
as `25H2` or `latest`. It should request media only through Microsoft's public
flow, download to a root-owned temporary file, verify Microsoft's current hash
and the `Windows 11 Pro` WIM label, then atomically move the ISO into the
mutable media directory.

The operation should save a root-readable manifest beside the ISO with release,
locale, filename, SHA-256, source-page URL, and retrieval time. It must refuse
to replace media once a managed disk exists unless an explicit refresh command
is requested. Replacing ISO media must never alter the installed guest or
silently change its target release.

This needs a browser-compatible Microsoft-supported mechanism before it can be
promised as fully automatic. The public page documents the interactive flow and
24-hour URLs but no automation API contract. A scraper of private web calls may
work and fail without notice. Do not put that in a Nix derivation or a background
timer. If the project accepts that maintenance risk, isolate it in the
privileged runtime helper, test it against saved redacted page fixtures, require
an explicit acknowledgement of Microsoft terms in the Nix option, and fail
closed when the flow, hash, or WIM metadata changes.

A fixed-output `fetchurl` remains useful only for a reviewed, dated release
with a known hash and a still-valid direct URL. It cannot implement a latest
channel because the source bytes and hash change, and the official link expires.
Do not use a Nix build sandbox, substituter, or public cache to distribute the
consumer ISO.

## Validation and limits

I reviewed the named module, templates, desktop policy, runbook, and generated
artifact check definition. I evaluated the desktop package versions with Nix.
No desktop build, activation, Windows installation, or guest execution ran.
The working tree already contained unrelated changes; this note is the only
file added for this review. Source pages were retrieved on 2026-09-24.

The source set is limited to Microsoft Learn and Microsoft Lifecycle, QEMU,
and virtio-win's official project documentation. Microsoft documents Windows
requirements and unattended behavior, but does not prescribe QEMU device XML.
Libvirt schema validation and QEMU package versions therefore remain local
observations, not a Microsoft compatibility certification.

## Implication for this repository

Fix the UAC and OpenSSH bootstrap blockers before activating a fresh Windows
install. Replace manual ISO staging with a root-owned runtime acquisition
workflow only after selecting a supported way to obtain Microsoft's ephemeral
link. Then add a small, repeatable runtime acceptance procedure to the Windows
VM workflow and runbook. Keep the current virtual-hardware shape and the
conservative package-removal policy until measurements identify a specific
resource problem.

## Implementation follow-up, 2026-09-24

The pinned MSDL client resolved Microsoft's signed URL for the declared
25H2 English x64 v2 ISO. The download matched Microsoft's published SHA-256.
The client uses an undocumented web flow, so the Nix declaration pins the
product ID, filename, and hash and fails closed if they diverge. It does not
claim automatic adoption of future Windows releases.

The first media preflight exposed a separate defect: the verified Microsoft
ISO's ISO9660 view contained only `README.TXT`, which directs readers to its
UDF filesystem. The former libarchive-backed FUSE inspector therefore could
not see `sources/install.wim`. This matches the [libarchive UDF support
report](https://github.com/libarchive/libarchive/issues/1036). A userspace
7-Zip UDF extraction found `sources/install.wim`; `wiminfo` identified
`Windows 11 Pro` at index 6. The preflight now extracts only that fixed path
to a temporary disk file and runs WIM inspection as the unprivileged media
inspector. The temporary file is removed after the check.

Generated artifacts and the full desktop system build passed after the
bootstrap changes. The persistent guest remains uninstalled.

## Local installation acceptance, 2026-09-24

A disposable libvirt session guest used the verified Microsoft ISO, the
rendered answer file and provisioning scripts, Secure Boot, TPM 2.0, and the
declared installer disk topology. Windows Setup installed the selected
Windows 11 Pro image, rebooted through OOBE, and ran the public baseline.
The first boot exposed several paths that static evaluation could not test:

- Microsoft's DVD bootloader required a key before Setup would start from a
  blank disk. Fresh installs now send a boot key during that prompt; resume
  deliberately leaves the prompt unanswered so a partially installed disk
  boots. The public Windows 11 Pro KMS client key in the `windowsPE` answer
  selects the edition without activating Windows, as described by
  [Microsoft's setup-key guidance](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/work-with-product-keys-and-activation-auth-phases?view=windows-11)
  and [key table](https://learn.microsoft.com/en-us/windows-server/get-started/kms-client-activation-keys).
- The seed ISO builder named the `osirrox` alias, which cannot write an ISO.
  Selecting the actual `xorriso` executable fixed seed creation.
- A registry `Run` entry did not retry failed provisioning after autologon.
  An elevated task with an interactive logon principal did retry it, using
  the [documented ScheduledTasks principal options](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskprincipal?view=windowsserver2025-ps).
- [PnPUtil documents exit code 259](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-return-values)
  when no device needs a supplied driver or a better driver is active. The
  driver stage now accepts that result on retries and avoids reinstalling an
  already present guest agent.
- A fresh OpenSSH Server had no host keys when configuration validation ran.
  Generating keys first made the validation pass. Sysinternals Autologon is a
  GUI executable, so waiting on its process supplied a reliable exit code.
- Recreating an existing Explorer registry key failed under the interactive
  administrator token. The registry helper now creates only missing keys.
  Appx removal can report a missing package path; the baseline now records
  each removal error and checks the actual installed and provisioned state.

The final baseline returned `PASS`. After a clean shutdown, the same disk
cold-booted with the declared VirtIO SCSI runtime definition and no installer
media. Windows reported Pro build 26200; the guest agent responded, TPM was
present, the management-address SSH listener accepted a local connection,
and the retry task had removed itself. The separate session network required
test-only DHCP subnet values. This run does not exercise host ingress through
the production system libvirt bridges or Windows activation. The persistent
guest was not installed or activated by this acceptance test.
