# Windows edition and image-customization decision

Research date: 2026-09-03

## Decision

Use **Windows 11 Pro 25H2 x64** for `windows-runtime`. Microsoft publishes the
production multi-edition ISO and its SHA-256 publicly, the private GUI workload
targets ordinary Windows 11, and activation can occur later with the matching
valid Pro license. A clean test VM must still pass the private application,
updater, autologon, and reboot acceptance tests before production credentials
are added.

The exact desktop manifest is
`Win11_25H2_English_x64_v2.iso`, image name `Windows 11 Pro`, and SHA-256
`768984706B909479417B2368438909440F2967FF05C6A9195ED2667254E465E3`.
Microsoft's generated CDN link expires after 24 hours, so the Nix declaration
records the stable source page and content identity while the verified ISO is
retained privately. See `docs/windows-iso-source-research.md` for the full
source-channel analysis.

Windows 11 Enterprise LTSC 2024 remains an operationally attractive
alternative for a fixed workload, but production media is available only
through authenticated licensing channels. The public ISO is a 90-day
Evaluation and cannot be the live VM. Enterprise LTSC also adds an application
support question that Pro avoids. It receives quality updates through
2029-10-10 and no normal feature updates. See the
[LTSC 2024 feature and servicing description](https://learn.microsoft.com/en-us/windows/whats-new/ltsc/whats-new-windows-11-2024),
[LTSC overview](https://learn.microsoft.com/en-us/windows/whats-new/ltsc/overview),
and [lifecycle entry](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-enterprise-ltsc-2024).

Use **Windows 11 Enterprise 25H2** only when its commercial features and
virtualization rights are required and matching licensed media is available.
Microsoft identifies 25H2 and 24H2 as the releases for broad enterprise
deployment. Windows 11 26H1 is a hardware-specific release for select new
devices, not the right image for this x86 KVM guest. See the
[Enterprise lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-enterprise-and-education),
[Home and Pro lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-home-and-pro),
and [26H1 deployment guidance](https://learn.microsoft.com/en-us/windows/release-health/status-windows-11-26h1).

Do not use Tiny11, Tiny11 Core, nano11, ReviOS, AtlasOS, or a broad debloat
preset for the production VM. Do not add NTLite to the default build path.
The current design, an official Microsoft ISO plus a small generated answer
ISO and reviewed PowerShell, is the right foundation.

## Edition comparison

| Edition | Servicing horizon | Fit for this VM | Decision |
| --- | --- | --- | --- |
| Windows 11 Enterprise LTSC 2024 | Monthly quality updates through 2029-10-10; no normal feature updates | Dedicated workload fit, but production ISO requires authenticated acquisition and vendor support is less explicit | Alternative only with production media |
| Windows 11 IoT Enterprise LTSC 2024 | Ten years, through 2034-10-10 | Technically attractive, but licensed only for fixed-function specialized devices | Use only with written licensing confirmation |
| Windows 11 Enterprise 25H2 | Normal feature channel; support through 2028-10-11 | Commercial features and rights, but production ISO is authenticated | Alternative when required |
| Windows 11 Pro 25H2 | Normal feature channel; support through 2027-10-13 | Public production multi-edition media and ordinary Windows 11 application compatibility | Selected |
| Windows 11 Pro for Workstations | Same normal channel as Pro | Its workstation storage and hardware-scale features do not help a 4-vCPU VirtIO guest | No benefit here |
| Windows Server 2025 | Server servicing model | At least one required private application supports client Windows 10 and 11 rather than Server | Reject for this guest |
| Windows 10 Enterprise LTSC 2021 | Support ends 2027-01-12 | Old 21H2 base with less than one year of support remaining | Reject for a new build |

### Why neither LTSC Evaluation nor IoT LTSC is selected

Windows 11 IoT Enterprise LTSC 2024 is a full, binary-equivalent Windows
Enterprise product with a ten-year lifecycle. The constraint is licensing,
not application performance. Microsoft states that IoT Enterprise is for
fixed-purpose devices and that the volume-licensed LTSC product cannot replace
desktop Windows for general-purpose computing. The dedicated application runtime
resembles a fixed-purpose appliance, but the same VM will also be used for
debugging and development. Do not make a legal interpretation from technical
similarity. Use IoT only if the seller confirms this exact VM and usage in
writing. See the [IoT Enterprise overview](https://learn.microsoft.com/en-us/windows/iot/iot-enterprise/overview),
[IoT LTSC volume-license restriction](https://learn.microsoft.com/en-us/windows/iot/iot-enterprise/deployment/volume-license),
and [IoT LTSC release history](https://learn.microsoft.com/en-us/windows/iot/iot-enterprise/whats-new/release-history).

The public IoT and Enterprise LTSC downloads are 90-day evaluations. They are
appropriate for a disposable compatibility trial, not the live deployment.
The Enterprise Evaluation Center is also the download page referenced by this
repository's Windows-font package, but that package currently follows the
regular Enterprise 25H2 Evaluation ISO. Sharing a landing page does not make
either Evaluation ISO the released LTSC installation media.

Windows client Evaluation editions cannot be made into released editions by
entering a production key; using one for the persistent VM would require a
later clean installation. Production LTSC instead comes from Microsoft 365
admin center under **Billing > Your products > Volume licensing > View
downloads and keys**. See the
[Enterprise Evaluation Center](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise),
[Microsoft support guidance on client Evaluation media](https://learn.microsoft.com/en-us/answers/questions/735046/how-can-i-activate-an-evaluation-version-of-window),
[Microsoft volume-license download instructions](https://learn.microsoft.com/en-us/microsoft-365/commerce/licenses/download-vl-products),
and [product-key instructions](https://learn.microsoft.com/en-us/microsoft-365/commerce/licenses/product-keys-for-vl).

### Licensing and activation

This decision records the owner's explicit assumption that the available
license covers this guest; it does not put the key in Git or validate the
contract. Do not assume an OEM Windows key from another computer licenses a
different guest.
Microsoft's virtual-desktop guide says OEM licenses typically do not include
virtualization rights. Commercial Windows Enterprise, VDA, and qualifying
Microsoft 365 products have specific local and remote virtualization rights,
and some require a qualifying operating system on the licensed device. The
current Microsoft Product Terms allow up to four local virtual operating
system environments in specified volume-licensing cases. The exact entitlement
depends on whether the license is assigned per user or device and how the VM is
accessed. Procure the license for a Windows VM on a NixOS host explicitly. See
[Microsoft's Windows 11 virtual desktop licensing guide](https://www.microsoft.com/licensing/guidance/Windows-11-Licensing-for-Virtual-Desktops),
[Windows Commercial Licensing overview](https://learn.microsoft.com/en-us/windows/whats-new/windows-licensing),
and the current [Windows Desktop Product Terms](https://www.microsoft.com/licensing/terms/en-US/productoffering/WindowsDesktopOperatingSystem/OL/).

## Private application compatibility

Vendor names, adapters, account details, and application-specific acceptance
steps do not belong in this public repository. The reviewed private
requirements target ordinary Windows 11, which makes Pro the least surprising
support target. They do not establish Enterprise LTSC support. If LTSC is
reconsidered later, test the exact private application versions and confirm
vendor support before adding production credentials.

Start the trial with the declared 4 vCPUs and 8 GiB RAM. Run the full private
workload, then examine committed memory, paging, host QEMU resident memory, and
UI responsiveness. Raise the guest to 12 or 16 GiB only if measurements justify
it. This preserves host memory for interactive development. The current
unpinned vCPUs and reduced CPU-share weight matter more to host responsiveness
than removing a few Windows packages.

## Tool comparison

### Recommended tools

| Tool | Best use | Recommendation |
| --- | --- | --- |
| Repository-owned `Autounattend.xml.in` and PowerShell | Auditable source of truth for this one VM | Keep |
| Windows System Image Manager (Windows SIM) | Validate the answer file against the exact WIM or ESD | Add as a release check |
| Schneegans Unattend Generator | Explore settings and generate a reference answer file, including VirtIO/QEMU setup | Use as a reference; never submit real secrets |
| Sven Groot GenerateAnswerFile | Open-source CLI/library with JSON input for common unattended settings | Optional if typed generation becomes valuable |
| NTLite | GUI-driven offline update and driver integration, dependency-aware component review | Use only for a measured image-servicing need |
| Windows Configuration Designer | Apply `.ppkg` configuration to existing fleets without rebuilding an image | Unnecessary for one fresh-installed VM |
| Packer QEMU builder | Produce generalized golden images or many disposable clones | Add only when repeated image builds justify it |

Microsoft recommends authoring or validating every answer file in Windows SIM
against the actual target image, and revalidating it when reused because
settings and defaults can change. Windows also caches the answer file on the
installed machine, so Microsoft directs administrators to delete the cached
copy after its final setup pass. See
[Microsoft's answer-file best practices](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/wsim/best-practices-for-authoring-answer-files)
and [Windows SIM validation](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/wsim/validate-an-answer-file).

The [Schneegans generator](https://schneegans.de/windows/unattend-generator/)
is the best browser-based design aid reviewed. Its
[usage documentation](https://schneegans.de/windows/unattend-generator/usage/)
supports a separate `unattend.iso`, VirtIO drivers, QEMU guest tools, and the
QEMU guest agent. Its implementation is an
[open-source .NET library](https://github.com/cschneegans/unattend-generator/).
It also documents that Setup copies answer files containing credentials into
`C:\Windows\Panther`. Generate examples without passwords in the web service,
review the XML, then keep the final template in this repository. The existing
runtime renderer is safer for secrets than entering them into any website.

[GenerateAnswerFile](https://github.com/SvenGroot/GenerateAnswerFile) is the
most suitable standalone CLI alternative found. It supports EFI disk layouts,
local accounts, autologon, image selection, first-logon scripts, and JSON
configuration. It explicitly warns that answer-file passwords are recoverable.
It does not cover every custom setting in the current template, so replacing a
small reviewed XML template with it would add a dependency without reducing
risk today.

Windows Configuration Designer produces provisioning packages without making
a new Windows image. Microsoft describes this as useful for configuring tens
to hundreds of existing endpoints. That is useful if this later becomes a
fleet, but it is an extra layer for one VM already provisioned by PowerShell.
See Microsoft's [provisioning package overview](https://learn.microsoft.com/en-us/windows/configuration/provisioning-packages/provisioning-packages).

Packer's QEMU builder can create KVM images from scratch and its documented
Windows flow uses an answer file on separate media. It becomes useful when a
generalized, credential-free base must be rebuilt regularly or cloned into
several guests. The direct installer already implemented has fewer state
transitions for one persistent VM. See the
[Packer Windows unattended guide](https://developer.hashicorp.com/packer/guides/automatic-operating-system-installs/autounattend_windows)
and [QEMU builder](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu).

### NTLite

NTLite is the best full image-customization GUI in this comparison. It can
edit ISO, WIM, ESD, and installed systems; integrate cumulative updates,
Defender definitions, drivers, registry settings, and post-setup commands;
generate unattended setup; and automate builds with presets and a CLI. It
supports Enterprise and IoT Enterprise LTSC 2024. See its
[feature list](https://ntlite.com/features/),
[unattended setup documentation](https://ntlite.com/docs/unattended/), and
[component compatibility controls](https://ntlite.com/docs/components/).

Its strengths do not make it the right default here:

- Windows 10 or later is required to edit current Windows images, so the NixOS
  host would need a separate Windows image-factory VM.
- Commercial use requires a Professional or Business license. The current
  published prices are EUR 90 and EUR 250 before tax. See
  [NTLite pricing and license tiers](https://ntlite.com/pricing/).
- Component removal creates a new servicing obligation. NTLite documents that
  updates on a lite installation can fail when update dependencies were
  removed, requiring its Host Refresh workflow to lay the full image back over
  the installation. See the
  [Host Refresh documentation](https://ntlite.com/docs/guides/host-refresh/).
- A proprietary preset is less transparent than the short PowerShell allowlist
  already stored and tested in this repository.

If NTLite becomes necessary, restrict it to an ephemeral image-factory VM and
use it only to integrate Microsoft updates, Defender definitions, and pinned
VirtIO drivers. Export and version the preset, pin the NTLite version and input
ISO hash, preserve Windows Security compatibility, and make every component
removal an individually reviewed allowlist item. Do not apply its General or
Lite removal template wholesale.

### Tiny11 and other broad Windows modifications

The name Tiny11 needs a distinction. Prebuilt Tiny11 images are modified
Windows media from a third party and cannot be matched to Microsoft's ISO hash.
The official [tiny11builder](https://github.com/ntdevlabs/tiny11builder) is an
open-source script that transforms an official ISO using DISM and Microsoft's
`oscdimg`. The regular builder remains serviceable, but it removes Edge,
OneDrive, Quick Assist, media components, and a fixed list of applications.
Its own documentation notes that removed applications may reappear and WinGet
may need repair. Those are poor properties for a long-lived application runtime.

Tiny11 Core is categorically unsuitable. Its author says it is for quick
development testbeds, cannot receive updates or add features, removes the
Windows component store and recovery environment, and disables Defender.
[nano11](https://github.com/ntdevlabs/nano11) is even more explicitly
experimental. Either may be useful for disposable compatibility tests with no
credentials. Neither belongs near production credentials.

[UnattendedWinstall](https://github.com/memstechtips/UnattendedWinstall) is
transparent and works with an official ISO, but its default recipe removes
almost every UWP application including Edge and OneDrive, changes services and
scheduled tasks, and disables automatic updates in favor of notifications.
The project describes the file as optimized for personal use. Reject that
baseline for this VM.

[Winhance](https://github.com/memstechtips/Winhance) has a good UI, can export
answer files, and exposes individual choices. It is useful for discovering a
setting and its implementation. Its own repository says it is still under
development. Treat generated output as review material, not as an implicitly
trusted production preset.

[Sophia Script](https://github.com/farag2/Sophia-Script-for-Windows) is the
best of the general post-install tweak collections because it exposes granular
functions and corresponding restore operations. It is still a large moving
dependency. Copy only a specific, understood operation into the local
bootstrap when it solves a measured problem.

[WinUtil](https://github.com/ChrisTitusTech/winutil) is broad and actively
maintained, but its documented quick start downloads and executes the current
network version of a script as Administrator. Do not use that pattern on this
guest. A pinned commit and a reviewed function could be evaluated in a lab,
but the preset adds no value over the current explicit baseline.

AtlasOS and ReviOS are also broad playbooks. Atlas now recommends keeping
Defender and Windows mitigations, but its playbook still offers automated
removal and performance policies across the OS. ReviOS currently defaults to
disabling Defender and pausing automatic updates, and removes components from
WinSxS. See the official
[Atlas playbook configuration](https://github.com/Atlas-OS/Atlas/blob/main/src/playbook/playbook.conf)
and [ReviOS feature inventory](https://revi.cc/docs/features). Their gaming and
latency goals do not match a supportable financial runtime.

## Recommended unattended configuration

Keep the current split between a trusted base ISO, public template, volatile
secret rendering, and private application provisioning:

```text
Microsoft x64 ISO + published SHA-256
  -> repository-owned Autounattend template
  -> root-only answer ISO rendered under /run
  -> clean KVM install with UEFI, Secure Boot, and TPM 2.0
  -> reviewed, idempotent PowerShell baseline
  -> private application installer and credentials
  -> machine-readable acceptance tests
```

The answer file should remain small:

- Select the exact image name found in `install.wim` or `install.esd`.
- Use GPT, EFI, MSR, Windows, and recovery partitions.
- Keep Dynamic Update disabled during Setup so the build input is known, then
  install current quality updates before accepting the guest.
- Do not bypass TPM, Secure Boot, CPU, or memory requirements. The virtual
  hardware already satisfies them.
- Set locale, time zone, computer name, local Administrator, autologon, and the
  accepted UAC policy explicitly.
- Run exactly one first-logon bootstrap command. Microsoft documents that
  multiple `FirstLogonCommands` entries can start concurrently despite their
  order fields. See the
  [FirstLogonCommands order reference](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-firstlogoncommands-synchronouscommand-order).
- Keep all product keys, passwords, service details, and proprietary installers
  out of Git and out of the static template.

The public baseline should continue to keep Defender, Firewall, Windows
Update, BITS, cryptographic services, Task Scheduler, Event Log, WMI, Windows
Installer, .NET support, Edge/WebView2, the component store, and recovery
infrastructure. Disable only hibernation, sleep, Game DVR, consumer suggestions,
peer update delivery, and unused nested-virtualization features. Remove only a
short allowlist of consumer AppX packages. Use the Balanced power plan and a
system-managed page file. A High Performance plan can increase idle host power
and does not help a mostly waiting GUI runtime.

The normal-channel configuration pins the Windows Update target release to
Windows 11 25H2. Change it only after a backup-backed upgrade test. LTSC does
not need that feature-release pin. Both channels must
continue receiving monthly quality updates and Defender signatures. Schedule
reboots outside application operating hours; do not pause updates
indefinitely.

## Release checks before the first production install

The current implementation is close to this target. Keep its verified
Microsoft ISO, volatile seed, pinned VirtIO media, single bootstrap command,
restricted OpenSSH management NIC, Sysinternals Autologon, balanced plan,
small AppX allowlist, and baseline test.

The configuration now selects `Windows 11 Pro` from a pinned Windows 11 25H2
multi-edition ISO and exposes verified installation media through a
read-only userspace filesystem owned by a dedicated unprivileged account. It
uses `wiminfo` to reject the ISO unless that exact image exists. This prevents
another release or edition from being used accidentally without exposing the
host kernel's filesystem parser to the staged ISO. It also deletes cached
`unattend.xml` and `Autounattend.xml` files
below `C:\Windows\Panther` after `oobeSystem`, then tests that the answer file
and transient password are absent.

Complete these remaining release checks:

1. **Validate with Windows SIM.** Validate the rendered, password-redacted
   answer-file shape against the exact selected ISO whenever the ISO hash or
   edition changes.
2. **Assert edition and servicing state.** Record product name, edition ID,
   build number, activation state, latest quality-update level, and baseline
   version in the guest status output.
3. **Assert application prerequisites.** Check .NET Framework 4.8, .NET 8,
   VirtIO storage/network drivers, QEMU guest agent, OpenSSH, and WebView2
   before private application acceptance.
4. **Keep an update-safe recovery point.** Make a cold, credential-free base
   backup after Windows and prerequisites pass, before live-account material
   is installed. A snapshot alone is not a backup.

The configured image name is `Windows 11 Pro`. If Microsoft changes the WIM
label, `windows-vm verify-media` lists the actual images and fails without
creating a disk; update the declaration only after reviewing that output.

## Acceptance test for the pinned Pro image

Use a clean installation of the pinned Pro image with the declared Q35, TPM,
Secure Boot, VirtIO, 4-vCPU, and 8-GiB definition. Do not add production
credentials until the base acceptance test passes.

The candidate passes only when all of the following work after a clean install,
all current quality updates, and two cold boots:

- Every required private application installs, launches, and updates using its
  documented framework and graphics dependencies.
- Every required private adapter loads without an edition-specific or WebView2
  dependency error.
- The private coordinator starts automatically after autologon and reconnects
  after a guest reboot and a temporary network outage.
- Scheduled tasks, OpenSSH key login, QEMU guest-agent shutdown, host-only
  management filtering, Windows Update, Defender, and Firewall all pass.
- Fifteen-minute idle and representative workload tests show acceptable
  host CPU, QEMU resident memory, guest commit, page faults, and disk writes.
- A monthly quality update installs and rolls back from the cold backup in a
  disposable copy.

If Pro fails an application test, diagnose the exact dependency before changing
editions or removing components. LTSC remains a separately qualified option,
not a performance shortcut.
