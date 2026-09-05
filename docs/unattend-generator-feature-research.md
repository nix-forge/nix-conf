# Unattend Generator features for the managed Windows VM

Research date: 2026-09-04

## Recommendation

Use Unattend Generator as a source of narrowly scoped ideas and regression
cases. Do not add the generator itself to the build and do not reproduce its
large menu of switches.

The repository already has the better architecture for this VM: Nix owns a
small reviewed answer-file template, the administrator password enters only at
privileged runtime, one first-logon dispatcher applies an idempotent baseline,
and the guest reports a machine-readable result. Replacing that with a web
generator or a generated XML blob would weaken reviewability and secret
handling.

Port these features, in this order:

1. Correct the OOBE settings. Change `ProtectYourPC` from `1` to `3`, remove the
   deprecated `NetworkLocation`, and stop treating `HideLocalAccountScreen` as
   meaningful on Windows client.
2. Fix the Delivery Optimization policy path and test its effective value.
3. Add supported low-risk developer and idle-resource policies: long paths,
   Edge background mode off, Edge Startup Boost off, Edge first-run UI hidden,
   and Automatic Restart Sign-On disabled.
4. Port upstream's input validation and provenance ideas: reject reserved
   account names and computer-name collisions, constrain unattended secrets to
   a tested character set, and expose a public configuration fingerprint in the
   guest status.
5. Adapt upstream's disk-selection safety to libvirt host-side assertions. Do
   not port its custom Windows PE deployment engine.
6. Keep app removal conservative, typed, edition-aware, and tested. Do not
   import the upstream bloatware catalog wholesale.

Keep Defender, Firewall, SmartScreen, Windows Update, Secure Boot, TPM, WinRE,
the Microsoft Store servicing path, Edge WebView2, and the system-managed page
file. The upstream project can generate settings that turn off or remove some
of these components, but those are poor defaults for a durable, networked VM.

The upstream source examined for this report is commit
[`8a362f03a8b97bc7e583643818be33444636bb43`](https://github.com/cschneegans/unattend-generator/tree/8a362f03a8b97bc7e583643818be33444636bb43).
It is MIT-licensed. If substantial code is copied instead of independently
implementing the documented behavior, preserve its copyright and license
notice as required by the upstream
[`LICENSE.txt`](https://github.com/cschneegans/unattend-generator/blob/8a362f03a8b97bc7e583643818be33444636bb43/LICENSE.txt).

## What the repository already does better

The comparison covered:

- `modules/nixos/virtualisation/windows-vm.nix`
- `modules/nixos/virtualisation/windows/Autounattend.xml.in`
- `modules/nixos/virtualisation/windows/Bootstrap.ps1.in`
- `modules/nixos/virtualisation/windows/Test-Baseline.ps1.in`
- `modules/nixos/virtualisation/scripts/windows-vm-render-seed.py`

The gap descriptions below refer to the files as they stood at the start of
this audit. They are implementation targets, so completed changes will make
some of the "current gap" cells historical.

Several current choices should remain unchanged:

- The production ISO is a local licensed input with an exact SHA-256 and an
  exact WIM image-name preflight. This is more reproducible than asking a web
  service to generate XML for whatever image is current.
- The password is read from a root-only file and injected into a volatile seed
  ISO. It does not enter Git, an evaluation trace, or the Nix store. Microsoft
  warns that answer files can contain credentials and recommends restricted
  ACLs and deletion of cached answer files. The current bootstrap does both,
  then removes the transient password
  ([Microsoft answer-file security guidance](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/wsim/best-practices-for-authoring-answer-files#improve-security-for-answer-files)).
- The renderer XML-escapes the secret, requires exactly two placeholders,
  rejects symlinks and overly broad file modes, and writes private outputs
  atomically. Upstream's optional password "obscuring" is only UTF-16 data plus
  a suffix encoded as Base64 in
  [`Users.cs`](https://github.com/cschneegans/unattend-generator/blob/8a362f03a8b97bc7e583643818be33444636bb43/modifier/Users.cs#L220-L237).
  It is not encryption and is not an improvement over the current runtime
  secret boundary.
- Fresh installation refuses to reuse the persistent qcow2, atomically creates
  a new disk, and keeps an installation marker until the guest passes its
  baseline and cold-boots from the runtime definition. That is safer than
  making a generic installer choose among arbitrary disks.
- There is one `FirstLogonCommands` entry. Microsoft documents that multiple
  `SynchronousCommand` entries now start at the same time, so a single
  dispatcher is the correct sequencing boundary
  ([Microsoft command ordering](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-firstlogoncommands-synchronouscommand-order)).
- The first-logon script copies itself locally, registers a retry, records a
  transcript and status, and removes the retry only after its test passes.
  Upstream's generated phase scripts are a useful design reference, but they do
  not replace this failure and retry protocol
  ([upstream script phases](https://github.com/cschneegans/unattend-generator/blob/8a362f03a8b97bc7e583643818be33444636bb43/modifier/Script.cs)).
- VirtIO media is pinned, Sysinternals Autologon is pinned and Authenticode
  checked, SSH accepts keys only, and the management firewall rule is limited
  to the host address.
- The baseline keeps security and management services enabled, uses the
  Balanced power plan, disables guest sleep and hibernation, and leaves the page
  file system-managed. These are sound appliance defaults.

## Priority findings

| Priority | Upstream idea | Current gap | Decision |
| --- | --- | --- | --- |
| P0 | Disable Express settings | `ProtectYourPC` is `1`, which enables Express settings | Set it to `3`; also verify Defender and SmartScreen remain enabled |
| P0 | OOBE cleanup | The template contains deprecated or inapplicable settings | Remove `NetworkLocation`; do not rely on `HideLocalAccountScreen` |
| P0 | Disable peer delivery | `DODownloadMode=0` is written under a legacy `CurrentVersion` path | Write the supported policy path and test it |
| P0 | Validate users | The Nix regex is strict, but reserved names and computer-name collision are not rejected | Add case-insensitive assertions |
| P0 | Deterministic disk choice | Disk 0 is assumed | Prove on the host that the installer has exactly one writable target disk |
| P1 | Long path support | Not enabled | Enable and test it |
| P1 | Edge idle controls | Not configured | Disable background mode and Startup Boost; hide first-run UI |
| P1 | Disable ARSO | Not configured | Disable the redundant post-update credential mechanism |
| P1 | Build provenance | Status records a hand-maintained baseline version only | Add a content-derived public recipe fingerprint |
| P1 | Structured app removal | Removal is a fixed PowerShell list and one policy is ineffective on Pro | Keep a small typed set, gate by edition, and verify results |
| P2 | Prevent update reboot | Only active hours are configured | Add only with explicit reboot-required reporting and a maintenance action |
| P2 | Explorer defaults | Only visual effects and screen saver are configured | File extensions and `This PC` are reasonable optional UX settings |
| P2 | Recovery and encryption checks | Neither WinRE nor BitLocker state is in the baseline result | Report and validate the selected policy; do not silently disable either |

## Changes worth porting

### Correct OOBE semantics

`ProtectYourPC=1` has the opposite meaning from the likely intent. Microsoft
defines values `1` and `2` as enabling Express settings and `3` as disabling
them. Upstream's `DisableAll` choice correctly emits `3`
([Microsoft `ProtectYourPC`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-protectyourpc),
[upstream `ExpressSettings.cs`](https://github.com/cschneegans/unattend-generator/blob/8a362f03a8b97bc7e583643818be33444636bb43/modifier/ExpressSettings.cs)).

Set `ProtectYourPC` to `3`, but do not pair it with upstream's SmartScreen or
Defender disabling options. Explicitly set the Windows shell policy
`HKLM\SOFTWARE\Policies\Microsoft\Windows\System\EnableSmartScreen=1` and the
Edge policy `HKLM\SOFTWARE\Policies\Microsoft\Edge\SmartScreenEnabled=1`, both
of which Microsoft supports on Pro
([Microsoft SmartScreen Policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-smartscreen),
[Microsoft Edge SmartScreen policy](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/smartscreenenabled)).
Add baseline assertions that Defender, Firewall, both SmartScreen policies, and
Windows Update remain available. This makes the privacy choice explicit without
accidentally treating security controls as telemetry.

Remove `NetworkLocation`. Microsoft marks it deprecated starting with Windows
10
([Microsoft `NetworkLocation`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-networklocation)).
`HideLocalAccountScreen` applies only to Windows Server, so it should not be
used as evidence that Windows 11 client OOBE is automated
([Microsoft `HideLocalAccountScreen`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hidelocalaccountscreen)).

Keep `HideOnlineAccountScreens` and `HideWirelessSetupInOOBE`. Both are
documented settings and fit a VM that creates a declared local administrator
and receives networking from libvirt
([Microsoft `HideOnlineAccountScreens`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hideonlineaccountscreens),
[Microsoft `HideWirelessSetupInOOBE`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hidewirelesssetupinoobe)).
Do not add `SkipMachineOOBE`; Microsoft's OOBE automation guidance explicitly
warns against using it
([Microsoft OOBE automation](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/automate-oobe)).

### Put Delivery Optimization under the supported policy key

The current bootstrap writes:

```text
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config
```

For a managed policy, Microsoft documents:

```text
HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization
```

with `DODownloadMode=0` for HTTP-only downloading and no peer-to-peer delivery.
This setting is supported on Windows Pro
([Microsoft Delivery Optimization configuration](https://learn.microsoft.com/en-us/windows/deployment/do/delivery-optimization-configure),
[Delivery Optimization Policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-deliveryoptimization)).

Move the value, remove the legacy write, and make `Test-Baseline.ps1` assert the
policy path and value. Mode `0` retains Windows Update downloads and content
hash checking; it does not disable servicing.

### Add low-risk resource and developer policies

The following upstream options are useful here and have supported Windows or
Edge policy surfaces:

- Set `LongPathsEnabled=1` at
  `HKLM\SYSTEM\CurrentControlSet\Control\FileSystem`. Microsoft notes that an
  application must also declare itself long-path aware, so this removes an OS
  limit for capable development tools rather than guaranteeing every program
  can use long paths
  ([Microsoft maximum path limitation](https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation),
  [upstream long-path implementation](https://github.com/cschneegans/unattend-generator/blob/8a362f03a8b97bc7e583643818be33444636bb43/modifier/Optimizations.cs#L311-L315)).
- Set the mandatory Edge policies `BackgroundModeEnabled=0`,
  `StartupBoostEnabled=0`, and `HideFirstRunExperience=1` under
  `HKLM\SOFTWARE\Policies\Microsoft\Edge`. These prevent Edge from keeping
  background processes and preloading at sign-in while avoiding unsupported
  Edge removal
  ([Edge background mode](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/backgroundmodeenabled),
  [Edge Startup Boost](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/startupboostenabled),
  [Edge first-run policy](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/hidefirstrunexperience)).
  Upstream writes the first two as recommended policies; mandatory values are
  preferable for this declared appliance baseline
  ([upstream Edge settings](https://github.com/cschneegans/unattend-generator/blob/8a362f03a8b97bc7e583643818be33444636bb43/modifier/Optimizations.cs#L501-L511)).
- Set `DisableAutomaticRestartSignOn=1`. Microsoft's ARSO documentation explains
  that Windows can store credentials across a restart to finish update setup.
  This VM already uses an explicitly accepted Sysinternals Autologon mechanism,
  so a second implicit credential mechanism adds no value
  ([Microsoft ARSO security behavior](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/component-updates/winlogon-automatic-restart-sign-on--arso-),
  [Windows Logon Policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowslogon),
  [upstream ARSO setting](https://github.com/cschneegans/unattend-generator/blob/8a362f03a8b97bc7e583643818be33444636bb43/modifier/Optimizations.cs#L830-L838)).

Every fixed policy should gain an adjacent baseline assertion. A registry write
that is not checked is merely an attempted customization.

### Strengthen account and secret validation

The current account-name regex already excludes most invalid characters and
limits the name to 20 characters. Add the parts that upstream checks and the
regex does not:

- reject `Administrator`, `Guest`, `DefaultAccount`, `SYSTEM`, `NETWORK
  SERVICE`, `LOCAL SERVICE`, `None`, and `WDAGUtilityAccount`, case-insensitively;
- reject an administrator name equal to `computerName`, case-insensitively.

These checks are implemented in upstream
[`Users.cs`](https://github.com/cschneegans/unattend-generator/blob/8a362f03a8b97bc7e583643818be33444636bb43/modifier/Users.cs#L105-L163),
and Microsoft separately documents the account-name constraints
([Microsoft local-account name](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-useraccounts-localaccounts-localaccount-name)).
Fail at Nix evaluation instead of discovering a collision during OOBE.

Upstream serializes its final answer file as 7-bit ASCII because its author
found arbitrary non-ASCII input unreliable in Windows Setup, even though the
XML declaration says UTF-8
([upstream serializer](https://github.com/cschneegans/unattend-generator/blob/8a362f03a8b97bc7e583643818be33444636bb43/Main.cs#L1169-L1197)).
Microsoft's own answer-file examples use UTF-8, so changing this repository to
the upstream declaration-and-ASCII mismatch is not justified. The useful
safety property is narrower: accept a printable ASCII unattended password,
reject control characters and non-ASCII input before seed creation, and add a
byte-level renderer test for UTF-8 without a byte-order mark or raw non-ASCII
bytes. That avoids relying on an untested corner of Setup, PowerShell, XML, and
Autologon while retaining a correctly encoded UTF-8 XML document. If
international credentials become a requirement, first exercise them in a
complete install test against the exact pinned ISO.

Do not port upstream's Base64 password mode. Microsoft describes hidden answer
file values as obfuscation and still recommends controlling and deleting answer
files; it is not a replacement for this repository's runtime secret handling
([Microsoft hide-sensitive-data guidance](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/wsim/hide-sensitive-data-in-an-answer-file)).

### Add a public recipe fingerprint

Upstream stamps generated output with the generator commit
([`Build.cs`](https://github.com/cschneegans/unattend-generator/blob/8a362f03a8b97bc7e583643818be33444636bb43/modifier/Build.cs)).
Adapt the idea to the existing status protocol:

- derive a non-secret fingerprint from the normalized answer template,
  bootstrap, baseline test, ISO SHA-256, image name, edition ID, release, and
  public VM schema version;
- write the fingerprint and those public identities to the guest status file or
  a root-readable registry key;
- have the host `baseline` command compare the running guest fingerprint with
  the currently declared fingerprint.

Do not hash the private provisioning directory or secret inputs into a public
manifest. A plain hash of low-entropy or identifying private data can disclose
more than intended and makes public code depend on private workload details.

This turns "PASS" into "PASS for the recipe I currently declared" and removes
the need to remember to bump a hand-maintained integer for every baseline
change.

### Adapt disk-selection safety at the libvirt boundary

The newest upstream disk logic selects a blank disk dynamically, then runs a
custom Windows PE, DiskPart, DISM, driver-injection, and BCDBoot pipeline
([upstream `Disk.cs`](https://github.com/cschneegans/unattend-generator/blob/8a362f03a8b97bc7e583643818be33444636bb43/modifier/Disk.cs)).
Its important property is refusing an ambiguous target, not the deployment
engine itself.

Keep native Windows Setup and add host-side proofs before first boot:

- parse the final installer domain XML and require exactly one writable
  `device="disk"` target;
- require that target to be the candidate qcow2, with the declared serial and
  virtual size;
- require every installation ISO and helper disk to be read-only;
- inspect the candidate with `qemu-img info --output=json` and reject unexpected
  backing files, format, or size;
- keep the current refusal to install over an existing persistent disk.

This is simpler and stronger for a libvirt domain whose complete device graph
is already generated by Nix. Porting the custom PE path would duplicate
Windows Setup's partitioning, recovery, driver, and boot logic while creating a
second installer to maintain.

### Make debloating explicit and edition-aware

Upstream separates Appx packages, Windows capabilities, and optional features
in its bloatware model
([`Bloatware.cs`](https://github.com/cschneegans/unattend-generator/blob/8a362f03a8b97bc7e583643818be33444636bb43/modifier/Bloatware.cs),
[`Bloatware.json`](https://github.com/cschneegans/unattend-generator/blob/8a362f03a8b97bc7e583643818be33444636bb43/resource/Bloatware.json)).
That classification is worth adopting. Its complete catalog is not.

Keep a small reviewed set of optional consumer Appx packages. Remove both the
installed package for existing users and the provisioned package for future
users, as the current bootstrap does. Microsoft documents that these are the
supported removal mechanisms and warns that certain system apps, including the
Microsoft Store, are not supported removal targets
([Microsoft inbox Store app guidance](https://learn.microsoft.com/en-us/troubleshoot/windows-client/shell-experience/modern-inbox-store-apps-troubleshooting-guidance),
[Microsoft provisioned-app servicing](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/preinstall-apps-using-dism?view=windows-11)).

For the pinned 25H2 image, sensible candidates to add to the existing reviewed
consumer list are `Microsoft.Copilot`, `Microsoft.BingSearch`,
`Microsoft.OutlookForWindows`, `Microsoft.PowerAutomateDesktop`,
`Microsoft.Windows.DevHome`, and `MSTeams`. These selectors come from
upstream's release-aware catalog, not from a stable Microsoft package-name
contract. Probe them on the exact image, treat a package that is not present as
informational, and fail only when a present package was requested for removal
but remains afterward.

For each declared package, capability, or feature, record one of:

- absent as requested;
- not present in this Windows image;
- still present, which fails the baseline;
- intentionally retained because another component depends on it.

The current `DisableWindowsConsumerFeatures` policy should not be considered an
effective Windows 11 Pro control. Microsoft's Experience Policy CSP marks the
corresponding `AllowWindowsConsumerFeatures` policy unsupported on Pro. Remove
the claim from the Pro baseline or gate it to an edition where Microsoft marks
it supported
([Microsoft Experience Policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience)).

Do not remove the Store, App Installer, Edge, WebView2, servicing stack,
Defender components, Photos, Calculator, or other shared runtime frameworks
without a measured need. A few dormant packages consume disk, not CPU. Broad
removal saves little interactive performance and increases update and
application-compatibility risk.

## Features to reject

| Feature | Why it should not be ported |
| --- | --- |
| Upstream generator as a build/runtime dependency | The desired output is small and auditable. Adding a large C# generator and option schema increases the trusted code and hides the exact Windows changes behind generated output. |
| Web generation or submitted credentials | The current local runtime renderer has the correct secret boundary. Credentials and activation keys must remain out of the web, Git, Nix evaluation, derivations, and store. |
| Base64 "obscured" passwords | It is reversible encoding, not encryption. The volatile, root-only seed plus post-OOBE deletion is stronger. |
| Product key in `Autounattend.xml` | It would be cached by Setup and placed in secret-bearing media. Select the WIM edition by exact image name and activate later through a private channel. |
| TPM, Secure Boot, RAM, CPU, or online-account bypasses | Upstream's `LabConfig` and `BypassNRO` paths are compatibility workarounds. This VM supplies supported TPM 2.0, Secure Boot, memory, CPU, and documented local-account settings, so bypasses only make failures less visible ([upstream `Bypass.cs`](https://github.com/cschneegans/unattend-generator/blob/8a362f03a8b97bc7e583643818be33444636bb43/modifier/Bypass.cs)). |
| Disable Defender, Firewall, SmartScreen, Smart App Control, or core isolation | These turn a performance profile into a security downgrade. Microsoft treats Defender, reputation-based protection, and virtualization-based protection as OS security controls ([Microsoft Windows security overview](https://learn.microsoft.com/en-us/windows/security/book/operating-system-security-virus-and-threat-protection), [Smart App Control](https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview), [memory integrity](https://learn.microsoft.com/en-us/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity)). |
| Disable Windows Update | A durable networked guest needs security and compatibility servicing. Pinning the target release and choosing maintenance times are safer than freezing patches. |
| Continuously move active hours | Upstream pairs `NoAutoRebootWithLoggedOnUsers` with a scheduled task that keeps moving active hours. That can defer necessary restarts indefinitely and obscures update state. |
| Disable System Restore or WinRE | Host snapshots are not a complete substitute for in-guest repair. Retain recovery unless backup and restore tests prove a replacement. |
| Unconditionally set `PreventDeviceEncryption=1` | Secure Boot and TPM can make automatic device encryption applicable. Microsoft recommends device encryption and treats prevention as an explicit deployment choice, not generic debloating ([Microsoft BitLocker overview](https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/), [OEM BitLocker guidance](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/oem-bitlocker)). Report the actual state and decide where encryption and recovery keys live first. |
| `VMModeOptimizations` | Microsoft's setting is for images generalized with `sysprep /mode:vm`, and its options can skip WinRE. It does not apply to this bare-ISO installation flow ([Microsoft `VMModeOptimizations`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-vmmodeoptimizations)). |
| Custom PE, DiskPart, DISM, and BCDBoot installation | It duplicates native Setup and recovery logic to solve a disk ambiguity that libvirt can eliminate before boot. |
| Delete compatibility junctions or alter the root ACL broadly | These are destructive filesystem changes with compatibility risk and negligible steady-state resource benefit. |
| Remove Edge, WebView2, Store, or component-store payloads | Windows and third-party applications depend on these servicing surfaces. Supported idle policies address the background-process concern without breaking dependencies. |
| Full upstream bloatware catalog | The catalog spans many Windows versions and user preferences. Absence from a dedicated appliance is not enough evidence that a component is safe to remove. |
| Command-line process auditing by default | The transient autologon credential is passed to Sysinternals Autologon as a process argument during provisioning. Recording command lines could persist that credential in the Security log. Process creation auditing without arguments can remain an optional diagnostic control. |
| CompactOS, a fixed or disabled page file, or blanket service disabling | These exchange disk or idle memory for CPU pressure, failure modes, and hard-to-diagnose compatibility issues. The existing dynamic memory and system-managed page file are safer. |
| RDP, Wi-Fi profiles, VMware, VirtualBox, Parallels, or other guest tools | The domain uses VirtIO, QEMU guest agent, SSH, SPICE, and libvirt networking. Extra remote-access and hypervisor agents add attack surface and background services. |
| Global PowerShell execution-policy relaxation | The bootstrap already invokes its pinned local script explicitly. A machine-wide relaxation is unnecessary. |
| AppLocker generated rules | The intended runtime user is deliberately an unrestricted local administrator. AppLocker needs a separate allowlisting design and would not establish a meaningful boundary against that administrator. |
| Upstream XSD as authoritative validation | Its component body is intentionally lax, so it can check XML shape without proving that settings exist in the selected Windows image. Windows SIM against the exact WIM remains the Microsoft-supported semantic validation method ([upstream XSD](https://github.com/cschneegans/unattend-generator/blob/8a362f03a8b97bc7e583643818be33444636bb43/resource/autounattend.xsd), [Microsoft answer-file validation](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/wsim/validate-an-answer-file)). |

## Update reboot policy needs a complete workflow

Upstream's `NoAutoRebootWithLoggedOnUsers=1` can be useful because this VM is
designed to stay logged in. Microsoft documents that it prevents automatic
restart while a user is signed in
([Microsoft Windows Update policy settings](https://learn.microsoft.com/en-us/windows/deployment/update/waas-wu-settings)).
It should not be copied by itself.

If the option is added later, require all of the following:

1. Windows Update remains enabled and scheduled.
2. Baseline or status output reports pending reboot state to the host.
3. The host control command offers an explicit graceful maintenance reboot.
4. Documentation assigns a maximum reboot deferral interval.
5. There is no task that continually moves active hours.

Without those pieces, a permanently auto-logged-in guest may never complete a
security update.

## Validation plan

Microsoft recommends validating manually authored answer files in Windows SIM
and revalidating them when they are reused because available settings and
defaults can change
([Microsoft answer-file authoring practices](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/wsim/best-practices-for-authoring-answer-files#always-validate-answer-files-in-windows-sim)).
`xmllint` or upstream's generic XSD can supplement this, but neither knows the
component catalog in the exact `install.wim`.

The implementation should use four validation layers:

1. **Pure repository checks.** Parse the rendered public template and assert
   the exact passes, component architecture, OOBE values, one first-logon
   dispatcher, disk ID and partition IDs, and absence of deprecated or bypass
   settings. Check the PowerShell with a parser and keep placeholder-count
   tests.
2. **Secret renderer tests.** Cover XML metacharacters, leading and trailing
   newline rejection, file modes, symlinks, missing and duplicate placeholders,
   printable ASCII constraints, no byte-order mark, output permissions, atomic
   replacement, and absence of the password from Nix-generated artifacts.
3. **Exact-image validation.** For every ISO or Windows release change, validate
   `Autounattend.xml` in Windows SIM against that ISO's exact WIM and perform a
   disposable full-install smoke test. Record the WIM image name and catalog
   version with the review evidence.
4. **In-guest acceptance.** Extend `Test-Baseline.ps1` to verify every adopted
   policy, expected optional-app state, Defender and Firewall state, SmartScreen
   policy, WinRE status, encryption state, no cached answer file or transient
   password, and the public recipe fingerprint. The host must reject a stale
   fingerprint even when the guest's old result says `PASS`.

For policy behavior that Microsoft does not document for Windows 11 Pro, prefer
an observable acceptance test over another registry tweak. If the effect cannot
be measured and the setting is unsupported, leave it out.

## Proposed module boundary

Do not mirror Unattend Generator's many booleans in Nix. Keep the module
opinionated and expose only decisions that are likely to differ between hosts:

- exact installation media identity and edition;
- resource limits and autostart;
- administrator name, secret-file path, and UAC choice;
- network attachments and host-only administration;
- target Windows release and maintenance window;
- a conservative optional-app removal set;
- an explicit encryption policy once backup and recovery-key ownership are
  designed;
- an optional automatic-reboot deferral policy only when the complete
  maintenance workflow exists.

Long paths, correct OOBE semantics, supported Delivery Optimization policy,
Edge idle controls, ARSO disablement, manifest reporting, security-service
checks, and safe disk topology are baseline invariants, not knobs. Keeping those
inside one deep module gives the configuration a small interface while the
module owns the difficult provisioning and verification work.
