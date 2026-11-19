# Reliable Darwin application settings and privacy permissions

Reviewed: 2026-10-16. Scope: personal Darwin workstations, macOS 27.0.1 on
Apple Silicon, and optional managed deployment. Repository baseline
`21237bdb8974bda44d4a8c591b50e542dd7dc6c3` plus the working configuration.
The reviewed lock pins nix-darwin to `4cff07de74b50e64bdd68cd4e722ab5b6b35ee48`
and Home Manager to `c58f54c733a7894d84fa2fdff26cc12088c4b78c`.

## Answer

The [2026-11-16 declarative identity follow-up](#follow-up-declarative-identity-without-mdm-or-paid-membership)
refines the current recommendation: preserve the verified upstream Handy release
through a pinned Nix package, and pilot persistent local certificate signing for
source-built Rift/OCR. Consent itself remains a macOS-owned state boundary. The
original investigation and implementation history follow below.

Build an application capability inventory and a read-only readiness command on
top of the existing configuration owners. Nix should apply supported settings,
explain the remaining consent steps, validate app identity, and report whether
the selected feature has actually been tested. Desired permissions and installed
policies must remain separate from observed authorization.

Start with personal Macs. Add managed delivery only if enrollment is deliberately
adopted. The supplied research is broadly correct about the limits of ordinary
Nix activation, but its shorthand grouping of Local Network with TCC obscures
important differences in testing and reset behavior. macOS 27's managed defaults
also need more precise eligibility and identity rules.

This investigation produced an executable policy-planning prototype and a staged
implementation plan. It did not install a new framework or alter privacy grants.
Native inspection found two signature failures that should be investigated before
rolling out automatic readiness checks.

## Findings and sources

### What the existing configuration already does

The [Darwin preferences module](../../modules/darwin/macos.nix) owns automatic
macOS updates, immediate password locking, Safari download handling, and user
preferences. The [security feature](../../modules/darwin/security/firewall.nix)
and [host firewall policy](../../hosts/darwin/macbook-pro-m4/local/firewall.nix)
already enable the application firewall and stealth mode, allow built-in signed
software, and disable automatic inbound allowance for downloaded signed apps.
The two firewall definitions currently overlap; preserve their behavior and give
future changes one owner rather than adding a third policy layer.

The pasted firewall and locking example would largely duplicate existing settings.
`LaunchServices.LSQuarantine` is a real pinned nix-darwin option with a documented
true OS default; making it explicit is a possible baseline clarification, not a
permission fix. Preferences such as suppressing `.DS_Store` files do not grant
protected folder access. [Pinned nix-darwin defaults](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/defaults/LaunchServices.nix),
[pinned firewall implementation](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/networking/applicationFirewall.nix).

The [home profile](../../homes/macbook-pro-m4/default.nix) selects the applications
below. Its [copy strategy](../../homes/macbook-pro-m4/local/compatibility.nix) and
[application registry](../../modules/home/macos/applications.nix) already provide
stable application locations. Extend that inventory; avoid a second installation
or registration manager.

### Supported delivery mechanisms

| Mechanism | Appropriate responsibility | Important limit |
| --- | --- | --- |
| nix-darwin | Machine defaults, inbound firewall, PAM, system launchd policy | Activation does not establish application privacy approval. |
| Home Manager | App files/preferences, browser policies, native messaging, user launch agents | Preference writes are distinct from protected authorization. |
| User consent | Feature-specific privacy decisions in the real app context | The framework can guide and verify; it cannot fabricate approval. |
| PPPC through MDM | Supported per-service policies with verified code identity | Requires user-approved MDM, device channel; manual installation is unsupported. |
| macOS 27 AppSettings DDM | Suggested privacy defaults | Requires supervision, user channel, AppKit applications, and user acceptance. |

Apple's [PPPC schema](https://github.com/apple/device-management/blob/09f249a06e7e3289930bf6d05f38fb562f748ebf/mdm/profiles/com.apple.TCC.configuration-profile-policy.yaml)
is the authority for service-specific behavior. PPPC can allow Full Disk Access
and targeted AppleEvents policies. It cannot silently allow camera, microphone,
screen capture, or Input Monitoring. Delegating ScreenCapture or ListenEvent
configuration to standard users still requires their action. Accessibility is
deprecated in macOS 27, not removed: Apple documents a nonblocking notification
and user-changeable state. Do not report it as immutable enforcement.

The [AppSettings declaration schema](https://github.com/apple/device-management/blob/09f249a06e7e3289930bf6d05f38fb562f748ebf/declarative/declarations/configurations/app.settings.yaml)
uses `Bundle-ID {Designated-Requirement}` keys and requires
`OrganizationJustification`. LocalNetwork accepts `None` or `Allow`; `None`
means no suggested default, not denial. Its privacy defaults include
Accessibility, Bluetooth, camera, dictation, location, microphone and Local
Network. They omit screen recording, Input Monitoring, Full Disk Access,
Files and Folders, and AppleEvents. Do not route those omitted services through
this declaration. The schema was checked at Apple's release commit
`09f249a06e7e3289930bf6d05f38fb562f748ebf`.

Login and background-item policy is separate. Apple's
[managed login-items payload](https://developer.apple.com/documentation/devicemanagement/servicemanagementmanagedloginitems)
requires user-approved MDM and cannot be manually installed. On a personal Mac,
keep Home Manager launch agents and app-native login registration distinct and
inspect user-visible background-item approval where applicable. Avoid enabling
both launch mechanisms for the same application. See Apple's
[background-task guide](https://support.apple.com/guide/deployment/depdca572563/web).

### Local Network needs its own treatment

Apple introduced Local Network privacy on macOS 15. Terminal/SSH command-line
children, root processes and launchd daemons are exempt; user LaunchAgents are
not. Therefore a successful SSH probe cannot establish GUI-app authorization.
The system-wide CIDR exclusions introduced in 15.5 bypass protection for every
program, and are unsuitable as an app-specific repair. Apple documents no
supported reset to undetermined on the reviewed OS; first-request testing needs
a fresh user or VM snapshot. `tccutil reset All` is not a Local Network reset.
[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

TN3179's general statement that MDM cannot configure this permission must be read
alongside the newer macOS 27 supervised consent-default declaration above.
Suggested defaults and silent grants are different operations. Keep both version
and mechanism in the capability table.

The [existing Local Network investigation](macos-app-local-network-research.md)
records a GUI-origin denial while an SSH-origin probe passed. Preserve its
separation of privacy enforcement, routes, DNS, gateway controls and app runtime.
An outbound firewall would add another network control; it would not set Apple's
Local Network permission. It is unnecessary for the initial framework.

### Applications and feature-specific requirements

“Required” below means required for the stated feature, not a recommendation to
approve every installed application's optional capabilities. Vendor documentation
is a starting point; installed bundle metadata and native feature tests complete
the evidence. Entries marked candidate require further application-specific
verification before inclusion in a generated consent checklist.

| Selected application or feature | Settings or approval to arrange | Observable acceptance check and evidence |
| --- | --- | --- |
| AeroSpace window management | Accessibility; one login owner; canonical copied executable | Move/focus a disposable window through a configured shortcut. Upstream documents accessibility attribution during development: [developer guide](https://github.com/nikitabobko/AeroSpace/blob/main/dev-docs/development.md). Installed signature currently fails; investigate first. |
| LinearMouse pointer/scroll customization | Accessibility; existing generated configuration | Verify the configured vertical scroll reversal and pointer behavior on the intended device. [Vendor accessibility guide](https://github.com/linearmouse/linearmouse/blob/main/ACCESSIBILITY.md). |
| OCR Capture region OCR | Existing shortcut and copied bundle; verify capture consent in this actual launch chain | Capture a harmless test image and compare clipboard text. The module warns about ad-hoc identity changes; establish which process owns any capture prompt. [Local implementation](../../modules/home/macos/ocr-capture.nix), [Apple capture controls](https://support.apple.com/guide/mac-help/mchld6aa7d23/mac). |
| Codex local services and VM access | Local Network where the GUI launches LAN commands; independently scoped command-network permissions | Run the same bounded connection through the GUI runner and SSH, labeling their origins. [Official command permissions](https://learn.chatgpt.com/docs/permissions), existing Local Network investigation. |
| Codex computer use, if enabled | Screen Recording and Accessibility for the responsible computer-use process; separate in-app app approval | Read and operate a disposable app window from the actual tool. Discover helper identity rather than granting the main bundle automatically. [Official computer-use guide](https://learn.chatgpt.com/docs/computer-use). |
| Moonlight LAN streaming | Local Network for discovery/connection; pairing; existing stream preferences | Discover, pair and stream from the selected host. Its [Info.plist](https://github.com/moonlight-stream/moonlight-qt/blob/master/app/Info.plist) declares LAN usage and Bonjour discovery. Viewing a stream is not a reason to grant local screen capture. Installed signature currently fails. |
| Zoom meetings | Microphone for voice, camera for video, Screen Recording for sharing; Accessibility only for selected remote-control features | Use the client's own audio/video test and share a harmless window. [Zoom permission guide](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0064868). |
| Microsoft Teams presentations | Screen & System Audio Recording for presentation; camera/microphone when calling | Present a test window and separately test sound/video. [Microsoft presentation guide](https://support.microsoft.com/en-us/teams/meetings/present-content-in-microsoft-teams-meetings). |
| Signal calls and sharing | Camera, microphone and screen recording only for the corresponding features; notifications if wanted | Place a test call and separately share a window. [Signal permissions](https://support.signal.org/hc/en-us/articles/360007062172-Signal-Permissions-OS-Notification-Settings). |
| Discord sharing | Screen Recording for the chosen capture mode; calling permissions are candidates to verify against the installed client | Use a private test channel and the native sharing picker. [Discord sharing guide](https://support.discord.com/hc/en-us/articles/26459694693783-How-to-Screen-Share-on-MacOS). |
| Chrome; Firefox/Zen/Helium browsing | OS camera/microphone consent and independent site permission when calling; capture consent when sharing | Test a selected origin in each actually used browser. Chrome documents both layers: [camera/microphone guide](https://support.google.com/chrome/answer/2693767). Do not assume identical policy support in every fork. |
| Bitwarden browser biometrics | Desktop native-messaging bridge, browser integration and user biometric enrollment; preserve signed app identity | Unlock the chosen browser extension through Touch ID. Broad Accessibility or Full Disk Access is not justified by this feature. [Bitwarden integration architecture](https://contributing.bitwarden.com/getting-started/clients/browser/biometric/), [existing investigation](bitwarden-browser-biometric-unlock-research.md). |
| Vorssaint | Existing login agent; leave built-in Launch at Login off; preserve explicit fan-control limitation | Check one running instance after login. Privacy grants cannot repair the missing trusted privileged-helper path. [Current module](../../modules/home/vorssaint.nix). |
| Wootility | USB/WebHID device selection for web use; preserve existing decision to avoid background startup | Detect the keyboard and read a profile; test firmware recovery separately. No blanket Input Monitoring assumption. [Existing vendor-backed research](wootility-80he-research.md). |
| Ghostty, VS Code, Neovim and development helpers | Candidate: selected protected-folder access or per-target Automation only when the workflow needs it | Open a disposable project in the selected location and test the exact integration. Do not grant Full Disk Access to all development tools. |
| Feishin, mpv, Moonfin, Spotify | Candidate: Local Network for a LAN media endpoint or discovery; selected-folder access for a local library | Play one item through the actual GUI/launcher and configured endpoint. Public cloud playback alone is not evidence of LAN need. |
| Steam, Prism Launcher | Candidate: Local Network for local discovery/multiplayer; controller/Bluetooth permissions only when exercised | Test the selected game/controller feature. Installation alone does not justify these grants. |
| LibreOffice, darktable, Notion, Actual | Candidate: user-selected document/library access; Actual service is disabled in the reviewed profile | Open a disposable document/library. No special grant identified for ordinary use; inspect optional features before adding requirements. |

The supplied app list is not a verified bundle-ID list. For example, native
inspection found `ChatGPT.app` with `CFBundleIdentifier=com.openai.codex`.
Use installed metadata rather than deriving identifiers from display names.

## Proposed framework

### Small public interface and ownership

Use one Home Manager interface, provisionally `macos.applicationCapabilities`,
whose app entries declare enabled features and their justifications. App modules
contribute requirements only when selected/enabled; host/home local configuration
chooses optional features. Avoid making the host repeat every permission.

A conceptual entry, not an option implemented by this research:

```nix
macos.applicationCapabilities.apps.moonlight = {
  enable = true;
  bundle = "Moonlight.app";
  features.localStreaming.enable = true;
};
```

The implementation resolves the copied-app root from Home Manager, joins the
existing canonical inventory, and obtains installed bundle ID, version,
designated requirement, signing kind, Team Identifier where present, executable
UUID and relevant helper attribution at runtime. A fixed copied path helps
identity stability but cannot repair invalid signing. Verify the resolved bundle
instead of editing vendor `Info.plist` usage descriptions after signing.

Keep policy decisions in the root repository. Native diagnostic packages belong
in the package repository if needed; target discovery changes are unnecessary.
Existing preference, browser and firewall modules retain their ownership.

### Planning and observation contracts

Generate a versioned manifest with app key, feature, service, reason, source,
minimum OS, identity expectation, delivery method, and required test origin.
Initial delivery is either existing declarative configuration or a user action.
The managed adapters remain disabled until separately implemented and validated.

Return explicit results: `ready`, `needs-user-action`, `blocked-identity`,
`unsupported`, `unknown`, and `not-applicable`. Include evidence time, OS build,
app version/identity and probe origin. A receipt is historical evidence, not a
cached authorization token. Never convert `desired=allow` or “profile installed”
into `observed=granted`. A manual approval receipt without a feature test remains
unverified. A successful feature probe establishes that feature, not unrelated
permissions.

Provide a read-only command, provisionally `hm-macos-readiness --check`, plus
machine-readable JSON and human-readable next actions. A separate interactive
`--guide` may open the canonical app or System Settings after an explicit user
invocation. Activation only refreshes manifests and compares metadata; it never
triggers consent requests, restarts apps, resets permissions or captures screens.
The default check must be useful over SSH while labeling GUI permissions unknown.

A helper calling Accessibility or screen-capture preflight observes its own
process context. It must not report another app's approval. For Local Network,
use a real app-origin diagnostic against a selected endpoint; private endpoints
and raw logs remain outside the repository. Use bounded probes and avoid sending
user files or recording unrelated screen content.

Keep `--check` free of writes, including receipts and caches. An explicitly
invoked `--verify` operation runs selected feature probes and records observations
atomically under private user state with one lock; preserve unmanaged settings
and record no credentials. Repeated checks must be idempotent.
Identity/OS changes make affected observations stale. Generation rollback removes
framework-owned configuration using its recorded ownership; it does not promise
to revoke macOS consent or restore an old TCC database.

### Recovery and managed delivery

Investigate signature failures before requesting additional permissions. Compare
package output, copied bundle and running executable; a copied-app failure alone
does not establish where corruption or packaging behavior originated. Repair
packaging at its owner and recheck registration, signing and feature behavior.
Do not silently re-sign vendor software during ordinary activation.

For supported TCC services, targeted reset is an explicit recovery action followed
by reapproval. Apple's [protected-resource reset guide](https://developer.apple.com/documentation/xcode/resetting-access-to-protected-resources-in-macos)
describes resets, not grants. Preserve ordinary denied choices and avoid blanket
resets. Local Network follows its separate version-specific recovery path.

If managed deployment becomes necessary, first verify enrollment and channel.
Render against an immutable Apple schema, validate composed code identity, and
fail on unsupported service/action combinations. AppleEvents also needs the
specific receiver requirement. Sign/export an artifact for MDM delivery; do not
claim that writing a local profile has enrolled the machine. Test delivery,
user choice and policy removal on a managed test Mac before production adoption.

## Validation and limits

### Executable planning evidence

The [prototype](../assets/darwin-application-permissions/plan.nix) is a pure Nix
function with [30 executable cases](https://github.com/nix-forge/nix-conf/blob/bb481eb2fab6bb064cee8efef4c0ec0653cd44b8/docs/assets/darwin-application-permissions/check.nix).
It exercises personal consent instructions, disabled entries, identity and
justification preconditions, macOS version gates, enrollment/channel eligibility,
PPPC allow/deny differences, macOS 27 Accessibility semantics, and DDM consent,
AppKit and identity requirements. Every output retains unknown observed state.

All 30 cases passed native evaluation on the reachable arm64 Mac running macOS
27.0.1. The local source files were combined into one expression and passed to
`nix-instantiate --eval --strict --json -` over SSH; no remote source checkout,
activation or profile installation was needed. Reproduce from a checkout with:

```sh
nix-instantiate --eval --strict --json \
  docs/assets/darwin-application-permissions/check.nix
```

This tests planning decisions only. The prototype is deliberately a small subset,
not a typed Home Manager module, exhaustive Apple schema validator, PPPC/DDM
renderer or native permission observer. In particular, its AppleEvents case is
not sufficient to generate a policy without receiver identity. Identity strings are checked for presence, not designated-
requirement syntax or installed signature validity. Native GUI consent,
policy delivery and app-update persistence remain untested. Markdown lint passed
for this note and the research index; all 13 relative link targets existed,
whitespace checks passed, and the repository-configured Gitleaks scan of this
note found no leaks.

### Read-only native observations

| Check on macOS 27.0.1 arm64 | Result | What it establishes |
| --- | --- | --- |
| `hm-macos-applications --check` | Passed for all 30 canonical registrations | Current registration consistency only. |
| LinearMouse 0.12.0, strict code verification | Exit 0, vendor team present | Signature validity at inspection time. |
| ChatGPT-named app 26.1013.31256, strict code verification | Exit 0, bundle ID `com.openai.codex`, vendor team present | Current bundle identity/signature; no privacy-state proof. |
| AeroSpace 0.21.3-Beta, strict code verification | Exit 1: resource seal expected but missing; ad-hoc signature | An actual signing failure requiring investigation. |
| Moonlight 6.1.0, strict code verification | Exit 1: resource seal expected but missing; ad-hoc signature | Same failure category; cause not established. |
| OCR Capture, strict code verification | Exit 0 | Current signature validity; no capture test performed. |

These commands ran over SSH. No app was restarted, no privacy database was read
or changed, and no app-specific grant was tested. Attempts to compare package
bundles through two conventional profile Applications locations found no bundle
there; source-versus-copy attribution remains unresolved. The failures do not
prove that either app is unusable or caused the previous Local Network incident.

### Native acceptance matrix for implementation

| Scenario | Required observable result |
| --- | --- |
| Fresh account, selected app not yet launched | Check reports unknown/user action without generating prompts. |
| Denial in the real GUI app | Feature fails clearly; readiness never reports ready from SSH success. |
| User approval and required app relaunch | Same-origin feature succeeds; receipt records current identity and origin. |
| Permission revoked after success | Next functional check detects failure or reports unknown; stale receipt is insufficient. |
| Invalid or changed bundle signature | Identity check blocks trusted-policy generation and requests investigation. |
| Same vendor identity after an app update | Retest real feature; do not assume persistence from a stable path. |
| Ad-hoc rebuild or changed executable UUID | Invalidate affected evidence and verify consent behavior again. |
| Login/reboot | One intended app instance; launch owner and approval state remain distinct. |
| Nix generation rollback | Config ownership is restored without overwriting unrelated preferences or privacy databases. |
| Missing app, disabled feature or unsupported OS | Not applicable or unsupported; no false grant and no unsolicited prompt. |
| Repeated checks or interrupted verification write | Same plan, no mutation during check; verification leaves no partial receipt. |
| Managed payload/default removed or user changes choice | Readiness reflects current behavior rather than policy presence. |

Use a disposable user or VM for denial/reset tests. Start with AeroSpace,
LinearMouse, Moonlight and the Codex GUI-origin connection; then Zoom/Teams and
OCR. Test one feature and one changed variable at a time. Do not automate a
production app restart while user work is active.

## Implementation plan and completion gates

1. **Investigate package identity failures.** Locate immutable source outputs for
   AeroSpace and Moonlight, compare them with copied apps, and determine whether
   packaging, copying or later modification breaks resource sealing. Put any fix
   and native package check in the owning repository. Completion: strict signing,
   canonical registration and the selected feature all pass on the Mac.
2. **Add the personal capability manifest and typed module.** Integrate with
   existing app selection and stable paths; add Nix assertions for impossible
   delivery, feature and identity combinations. Promote relevant prototype cases
   into the repository's evaluated checks. Completion: selected/disabled app
   behavior and invalid configurations are tested using actual module evaluation.
3. **Implement read-only readiness.** Add metadata inspection and clear unknown
   states before interactive guidance. Test malformed plists, missing apps,
   duplicate IDs, signature failure, paths with spaces, stale receipts and
   concurrent writes through the command's public interface. Completion: native
   metadata checks pass without prompting or changing settings.
4. **Add guided feature verification.** Perform the native matrix above on a
   disposable account, then the intended user context. Add consent instructions
   only for features backed by vendor sources and installed-artifact evidence.
   Completion: denial, approval, revocation, login, update and rollback results
   are recorded separately; unresolved cases remain visible.
5. **Optionally add managed adapters.** Only after enrollment is an explicit
   requirement, implement schema-backed PPPC and macOS 27 DDM with native managed
   acceptance tests. Completion: MDM confirms delivery and the actual application
   behavior matches the chosen user or administrator policy.

An independent read-only review checked the Apple policy claims and prototype
limits. Its finding about receipt ownership was resolved by separating read-only
checks from explicit verification writes.

The research supports this design and validates its central planning constraints.
It does not yet establish end-to-end permission reliability. The signature
failures and unperformed GUI acceptance matrix are explicit implementation gates.

## Implementation follow-through

The first personal-Mac implementation is now in the
[capability module](../../modules/home/macos/application-capabilities.nix) and
[readiness command](../../modules/home/macos/application-runtime/src/bin/hm-macos-readiness.rs). The
[operations runbook](../operations/darwin-application-readiness.md) records native
signing repairs, attended feature results, installation scope and remaining
lifecycle tests. The earlier “research only” statements above describe the
original investigation, not the subsequent implementation. Managed adapters
remain intentionally deferred.

## Follow-up: repeated prompts for source-built applications

Reviewed: 2026-11-16. Scope: the working configuration based on
`75b5bb62e1dd273b1647ab4fe56d2ef5948b4d0d`, with read-only inspection of
macOS 27.2.1 (26B131). This section updates the recommendation for recurring
prompts; the earlier dated observations retain their original scope.

### Answer and evidence

There are two separate problems. First-time consent is expected on an unmanaged
Mac: `macos.applicationCapabilities` generates an inventory and guidance, not
privacy grants. Repeated consent after an executable update can result from
build-specific signing identity. Apple explicitly describes this failure for
ad-hoc signed applications: the recorded designated requirement identifies one
code version, and a changed build can prompt again.
[Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

Native read-only checks found no MDM enrollment. `hm-macos-readiness --check
--json` returned exit 2, with all ten inventoried app identities valid and
protected capabilities unknown. `hm-macos-applications --check` passed all 27
canonical registrations. Unknown authorization is the intended output of this
inspection command; it does not prove denial.

`codesign -d -r-` on the installed Handy 0.9.8, Rift 0.7.2, Signal 8.32.0,
and OCR Capture 0.1.0 bundles showed default designated requirements containing
only a code-directory hash. LinearMouse instead had an Apple certificate/team
and application identifier requirement. Thus the inspected source-built apps
have valid signatures but lack an identity that survives changed executable
bytes. This is a confirmed structural risk and a strong explanation for prompts
after their updates; this investigation did not reproduce the GUI prompt or
establish that it explains every reported permission request.

The [historical Handy sealing repair](https://github.com/nix-forge/nix-conf/blob/9e24d0b1d0a9c375a5a4530a91927ec07fc0f145/overlays/temporary/handy-darwin-signature.nix)
restores integrity using ad-hoc signing. The
[Rift package](../../pkgs/pkgs/by-name/ri/rift/package.nix) also signs ad hoc.
Neither step supplies persistent developer identity. The pinned upstream
[Handy recipe](https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/pkgs/by-name/ha/handy/package.nix)
explicitly disables Tauri certificate signing. Repeating integrity checks or
Launch Services registration cannot change these designated requirements.

### Recommended fix

Keep Nix as the installation/configuration owner and add persistent signing for
explicitly selected locally built apps. Start with Handy and Rift. A usable
Apple Development identity was present in the Mac's Keychain at inspection time;
its public identity and private key need not be published in repository prose.
The existing OCR `signingIdentity` option demonstrates the local-Keychain
boundary, but is not yet a general app-update solution.

1. Preserve vendor signatures on distributed apps. Prefer a verified vendor-signed
   artifact when it provides the required functionality; do not assume a release
   download is signed without inspecting it. Retain source builds where needed.
2. For selected source builds, stage the complete bundle outside the Nix store
   and sign it using the persistent Apple-issued Keychain identity. Keep private
   signing material out of derivations and caches. Preserve reviewed entitlements
   and sign nested components in the correct order; avoid blanket deep re-signing.
3. Integrate this with the existing application lifecycle owner. Reject a missing
   or unusable signer before replacing the current app. Verify the staged signature,
   bundle identifier, signer and designated requirement. Never mutate a running
   executable; retain the previous complete app for recovery. Reuse an unchanged
   signed copy on a no-op activation.
4. Verify that the updated build satisfies the previous signed build's designated
   requirement, using `codesign --verify -R`, and verify in reverse where relevant.
   Apple documents this compatibility check in TN3127. Do not pin the DR to a
   particular executable hash or confuse changing CDHash with changed developer
   identity. Certificate renewal and signer changes need an explicit migration.
5. Reapprove once after migrating from ad-hoc to certificate identity, then test
   Handy microphone/paste and Rift window movement in the real GUI. Repeat after
   a changed build, ordinary relaunch, login and no-op Nix activation. Only that
   native acceptance can establish that the recurring symptom is fixed.

This is the smallest supported approach for these locally built apps. It does
not need MDM enrollment. MDM is a separate deployment choice for centrally managed
policy, with service-specific limits. Apple's
[PPPC schema](https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.TCC.configuration-profile-policy.yaml)
requires user-approved MDM and forbids manual installation. PPPC cannot silently
grant camera, microphone, ScreenCapture or ListenEvent. The macOS 27
[AppSettings declaration](https://github.com/apple/device-management/blob/release/declarative/declarations/configurations/app.settings.yaml)
adds supervised, user-scope consent defaults for supported services and AppKit
apps, still requiring user acceptance. It is not an unmanaged activation API.

### Updated Local Network recovery

The earlier no-reset guidance applies before macOS 27.2. Apple now documents
removing an app with the minus button in System Settings > Privacy & Security >
Local Network to reset its decision on macOS 27.2 and later. This is explicit
recovery, not an activation step or a grant. Do not use `tccutil reset All` as a
repair for repeated prompts. Apple also recommends Apple-issued signing for
reliable Local Network identity tracking.
[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

### Validation limits

Only read-only native inspection ran. No app was signed, replaced or restarted;
no permission was requested, reset or granted. SSH cannot reproduce GUI consent
or establish GUI-origin Local Network access. The user reports both initial and
repeated prompts, including Handy and Rift; a before/after GUI reproduction
remains necessary before attributing all recurrence to signing or claiming a fix.
No runtime configuration or package change is implemented by this follow-up.

## Follow-up: declarative identity without MDM or paid membership

Reviewed: 2026-11-16. Scope: the working configuration based on
`75b5bb62e1dd273b1647ab4fe56d2ef5948b4d0d`, pinned Home Manager
`a1293da7dd8e497e08d26173f97e2976b36a31ea`, and native artifact inspection on
macOS 27.2.1 (26B131). This follow-up supersedes the blanket recommendation to
locally re-sign Handy: a verified vendor-signed artifact is available.

### Recommended order

Keep application selection, versions, launch paths and signing policy declarative.
Treat the private signing key as persistent host state and privacy consent as
user-owned macOS state. Pure Nix builds produce the selected input; an idempotent
activation transaction installs the verified result. This fits the repository's
existing application owner and secret boundary without claiming that every part
of macOS can be reconstructed from a Nix derivation.

1. Package the vendor-signed Handy release on Darwin with an immutable version,
   fixed fetch hash and preserved signed bundle. Keep the Linux source package.
2. Pilot a persistent self-signed Code Signing identity for the locally built
   Rift and OCR bundles. No Apple account or paid membership is needed to create
   that identity. Do not promise permission persistence until native tests pass.
3. Extend the existing app lifecycle transaction to own both signing policies,
   preserving canonical locations, no-op rebuilds and recovery. Avoid a second
   post-copy script that repeatedly overwrites and re-signs active applications.
4. Keep capability guidance and feature verification. First-time consent and
   migration consent cannot be eliminated by a local signing declaration.

### Handy: verify and preserve upstream signing

The [0.9.8 release workflow](https://github.com/cjpais/Handy/blob/v0.9.8/.github/workflows/release.yml)
invokes signed builds. The [build workflow](https://github.com/cjpais/Handy/blob/v0.9.8/.github/workflows/build.yml)
imports a Developer ID certificate and passes the signing identity and notarization
credentials to Tauri. By contrast, the selected source-build strategy disables
certificate signing and the local sealing repair restores only ad-hoc integrity.
The recipient of a vendor-signed app does not need a developer membership.

Native inspection downloaded `Handy_aarch64.app.tar.gz` from the
[0.9.8 release assets](https://github.com/cjpais/Handy/releases/expanded_assets/v0.9.8)
into a private temporary directory and checked the published SHA-256:

```text
e6931a14805eac47878e5e80ba7de9395cebaf355d4b7e231fbdac532169e9a4
```

The extracted bundle had version `0.9.8`, identifier `com.pais.handy`, vendor team
`UWFLB4GC25`, and a Developer ID designated requirement scoped to its identifier
and vendor team. `codesign --verify --deep --strict --all-architectures` exited 0.
`spctl --assess --type execute --verbose=2` exited 0 and reported
`source=Notarized Developer ID`. The app was never executed or installed and the
temporary directory was removed. These results establish artifact identity and
Gatekeeper assessment at inspection time, not working dictation or migration.

The package should extract/copy the bundle without stripping, changing its
Info.plist, rewriting rpaths, wrapping its internal executable or re-signing it.
Place wrappers outside the bundle. Retain the vendor Team ID expectation in the
capability manifest and installation transaction. The binary package recipe belongs
to `pkgs/`; source selection and feature integration belong to the root repository.
A binary-preserving variant is a package choice, not another permanent patch to
the source package's ad-hoc sealing repair.

The pinned [Handy settings implementation](https://github.com/cjpais/Handy/blob/v0.9.8/src-tauri/src/settings.rs)
provides `HANDY_DISABLE_UPDATER` as a runtime override. Set it in the managed launch
environment so Nix remains the update owner. The current Darwin dictation launcher
executes the copied bundle directly and does not set this variable; wrapping only
the package's store CLI would therefore miss it. Cover every supported launch
route or enforce the existing application preference as well, without modifying
the sealed bundle. Verify ordinary Finder launch and login launch separately.

### Rift and OCR: persistent local signing, with a bounded claim

The inspected [Rift release workflow](https://github.com/acsandmann/rift/blob/2bb6647a18cde9ac44470d296988298c1093460d/.github/workflows/release.yml)
builds, combines and strips binaries without a certificate-signing step. Its
repository package constructs a bundle and signs ad hoc. Downloading its release
instead is not evidence of a vendor identity and would not itself solve this
problem. Keep the source-built package unless a verified signed release becomes
available.

Apple documents creating a self-signed Code Signing identity with Keychain Access.
It can identify successive local builds without a paid membership. This does not
provide notarization, Developer ID distribution trust or restricted entitlement
authorization.
[Apple Code Signing Tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html).

Use one persistent certificate/key pair, unique signing identifiers per app, and
the default designated requirement generated by `codesign`. Pin the public
certificate identity, not merely its human-readable name. Do not make a custom
identifier-only requirement that would match unrelated signers. Check compatibility
between different signed builds using Apple's requirement evaluator in both
directions. A passing comparison proves code identity compatibility; it does not
prove current Accessibility or microphone authorization.
[Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

Apple's archived signing guide makes self-signed acceptance subsystem-dependent.
Accordingly, "a self-signed certificate fixes all privacy prompts" is not a
validated conclusion. Do not install broad system-wide trust overrides or relax
Gatekeeper as a default. Test the actual Accessibility, screen-capture and other
features independently. A private CA can accommodate certificate renewal through
explicit requirements, but adds policy and key-management complexity; one persistent
local identity is the smaller first experiment.
[Apple TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).

Local Network remains a separate limit: Apple specifically recommends Apple-issued
signing for reliable identity tracking, and executable UUID and responsible-app
attribution also matter. Do not advertise a local self-signed certificate as its
universal solution.
[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

### Proposed Nix contract and lifecycle

Extend `macos.applications.protectedApps` with an explicit signing policy rather
than introducing a second installer. The following is a proposed interface, not
implemented configuration:

```nix
macos.applications = {
  signingIdentities.localApps = {
    certificateSha256 = "<public certificate fingerprint>";
    keychain = "${config.home.homeDirectory}/Library/Keychains/login.keychain-db";
  };

  protectedApps.rift = {
    bundle = "Rift.app";
    bundleId = "git.acsandmann.rift";
    source = "${pkgs.rift}/Applications/Rift.app";
    signing = {
      mode = "localCertificate";
      identity = "localApps";
    };
  };
};
```

Keep existing vendor entries on `preserveVendor`, retaining their required Team ID
and source-signature verification. Local mode must require a configured certificate,
explicit bundle identifier and reviewed signing layout. It cannot require a vendor
Team ID because a self-signed identity has none. Do not weaken vendor verification
to accommodate local apps. Use module assertions for impossible combinations.

Create/import the local identity once through an explicitly invoked setup step,
preferably Keychain Access Certificate Assistant. Record the public fingerprint in
Nix and keep an encrypted private backup. Normal activation checks availability
and fails clearly if the key is missing, locked or mismatched; it must never silently
create a replacement identity. Losing the key cannot be repaired by regenerating
a certificate with the same display name. Keychain access may need attended setup;
do not embed its password in Nix or assume headless SSH signing always succeeds.

A local signed output intentionally differs from its unsigned/ad-hoc source.
The current [lifecycle helper](../../modules/home/macos/application-runtime/src/bin/hm-macos-app-lifecycle-helper.rs)
compares source and installed signing hashes and enforces vendor Team IDs.
Merely adding `codesign` after copying would make that contract fail and could
cause perpetual replacement. Extend inspection and the installation record to
separate selected source identity from installed signed identity.

The activation transaction should:

1. Inspect the selected immutable input, signing policy, expected certificate and
   reviewed entitlement/layout description. Detect a true no-op before requiring
   an app quit or unlocked signing key. Verify the installed bundle as well as the
   private receipt; a receipt alone cannot authorize a no-op.
2. For a changed source or signing policy, require the app to quit, stage a complete
   private copy, and sign with native `codesign`. Sign reviewed nested components
   inside out; preserve intentional entitlements and runtime options. Do not use
   blanket `--deep` re-signing or add hardened-runtime exceptions indiscriminately.
3. Verify all architectures, expected signer, bundle identifier and nested code.
   Compare the candidate with the previously accepted designated requirement.
   A deliberate first migration from ad-hoc signing needs explicit handling;
   signer changes must not masquerade as ordinary compatible updates.
4. Recheck running state, install the complete bundle through the existing atomic
   exchange/journal mechanism, then register its canonical path. Store source
   selection, signing-policy digest, public certificate fingerprint and resulting
   signed identity atomically in private state. Retain the prior complete bundle.
5. Reuse that signed copy on identical rebuilds. A rollback restores a compatible
   retained signed artifact or re-signs the selected older input using the same
   identity after explicit downgrade handling. It cannot roll back macOS consent.

Extend the existing readiness output to describe certificate-based versus
build-specific identity as an advisory. Keep that assessment separate from signature
integrity and feature authorization; valid ad-hoc signing is not invalid code.
The existing per-feature manifest remains the consent checklist. Do not add direct
TCC database writes, automatic resets, repeated approval prompts or a parallel
permission daemon.

### Implementation gates and validation limits

Start with the binary-preserving Handy package and existing vendor lifecycle path;
that has stronger native evidence and requires no new local signer. Verify feature
and settings compatibility with the source package before switching it. Then pilot
local signing for Rift alone, extend to OCR after capture attribution is understood,
and generalize only after those results.

Native acceptance must cover one migration approval, actual GUI operation, a changed
build signed by the same identity, quit/relaunch, login, a no-op activation, an
interrupted update and generation rollback. Deliberate signer replacement should
be reported as a migration. Missing-key failure must preserve the installed app.
A disposable account is preferable for consent/revocation experiments.

For implementation validation, follow repository policy: Nix evaluation/assertions
and applicable static checks, upstream package checks, plus attended native evidence.
Do not introduce project-owned integration or snapshot suites. A successful build
or static signature comparison cannot replace the actual GUI acceptance matrix.

This research verified the published Handy archive and native signing/Gatekeeper
results, reviewed pinned release sources and the current integration, and made no
app installation, signing-key or permission changes. No self-signed candidate or
GUI permission-persistence test ran. GitHub API release enumeration returned HTTP
403 rate limiting; the official expanded release assets supplied the artifact name
and checksum instead. Therefore the recommendation is concrete and source-backed,
but source-to-vendor migration and local-certificate consent persistence remain
implementation gates.
