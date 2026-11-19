# MDM alongside nix-darwin

Reviewed: 2026-11-16. Scope: one personal Mac, nix-darwin/Home Manager,
macOS 27 permissions, and current hosted or self-hosted MDM options.

## Answer

MDM can complement Nix: Nix generates reviewed policy artifacts, and MDM delivers
policies through Apple's management channel. It is useful for centrally managed
security settings, supported privacy policies, inventory and device recovery.
For one Mac whose immediate problem is repeated Handy and Rift prompts, fix
persistent application signing first. MDM still identifies code through signing
requirements and cannot silently grant every permission.

A hosted pilot is reasonable if those additional management capabilities are
wanted. Self-hosting an MDM service solely to reduce consent prompts is not the
recommended trade-off. These are engineering recommendations, based on the
capability limits and operational requirements below, rather than native pilot
results.

## Findings and sources

### Enrollment does not require automated provisioning

Apple documents profile-based Device Enrollment, where the user installs an MDM
enrollment profile. On macOS 11 and later, Device Enrollment also establishes
supervision. Removing enrollment removes its dependent managed configurations.
[Apple Device Enrollment](https://support.apple.com/en-mide/guide/deployment/depd1c27dfe6/1/web/1.0).

Apple Business enrollment is not required for a third-party MDM's manual
Device Enrollment. SimpleMDM documents enrollment through a downloaded profile
and local administrator approval on an existing Mac. This route needs neither
an erase nor Automated Device Enrollment. Choose Device Enrollment, not the
separate Apple User Enrollment mode, for device-channel privacy policies.
[SimpleMDM getting started](https://simplemdm.pdq.com/hc/en-us/articles/9355287096091-Getting-Started-With-SimpleMDM),
[manual enrollment procedure](https://simplemdm.pdq.com/hc/en-us/articles/9355264362523-Enrollment-by-Link).

Manually approving the enrollment profile is different from manually installing
a PPPC policy profile. Apple's PPPC schema requires user-approved MDM,
device-channel delivery, and forbids manual PPPC installation. It does not require
Automated Device Enrollment. Signing a policy file locally does not supply MDM
authority.
[Apple PPPC schema](https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.TCC.configuration-profile-policy.yaml).

### What permissions improve

PPPC supports policies for Full Disk Access, protected folders, and Automation
with explicit sender/receiver code requirements. Accessibility has managed
policies, but macOS 27 displays a notification and permits user changes; Apple
deprecates that key in favor of AppSettings. PPPC cannot silently allow camera,
microphone, ScreenCapture or ListenEvent. The latter two can delegate changing
the setting to standard users. Local Network is not a PPPC service.
[Apple PPPC schema](https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.TCC.configuration-profile-policy.yaml).

macOS 27 AppSettings DDM offers user-accepted privacy defaults, including
Accessibility, camera, microphone and Local Network. It requires supervised
enrollment, user-channel delivery, AppKit applications, an organization
justification, and matching bundle/signing identity. Screen Recording, Input
Monitoring, Full Disk Access and Automation are absent from those defaults.
This can consolidate supported consent, but does not eliminate it. Confirm
eligibility and behavior for each actual Handy/Rift build; framework choice alone
is insufficient evidence.
[Apple AppSettings schema](https://github.com/apple/device-management/blob/release/declarative/declarations/configurations/app.settings.yaml).

Stable signing remains necessary. Apple's designated-requirement explanation
explicitly connects ad-hoc builds with renewed microphone prompts after code
changes. Using a build hash in an MDM code requirement would also bind policy to
one build, requiring policy updates. Use verified persistent signer/application
requirements rather than broad matching.
[Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).
See the [native signing investigation](darwin-application-permissions-research.md#follow-up-repeated-prompts-for-source-built-applications).

### Practical service choices

**SimpleMDM is the clearest documented API pilot for this repository.** Its
current pricing is US$3 per device/month monthly, or US$2.50 monthly equivalent
billed annually, with a full 30-day trial and billing by enrolled device count.
It supports custom profiles and an API for creating, updating and assigning them,
including user-scope profiles. This is evidence for a Nix-generated PPPC workflow,
not proof that its current service accepts arbitrary user-channel AppSettings DDM.
Require a native trial of that specific declaration before choosing it for macOS
27 consent defaults.
[Pricing](https://simplemdm.com/pricing/),
[custom profiles](https://simplemdm.pdq.com/hc/en-us/articles/55993143632155-Custom-Configuration-Profiles),
[API](https://api.simplemdm.com/v1).

**Jamf Now is a free small-device PPPC pilot candidate.** Its current product page
offers up to three devices free and custom profiles. Current documentation says
Mac custom profiles are device-channel only; user-scope custom profiles are
unsupported. Do not select it assuming that custom profile upload establishes
support for user-channel macOS 27 AppSettings DDM. The former Fundamentals plan
was merged into Jamf Now in 2023, so old Plus-plan comparisons are stale.
[Jamf Now](https://www.jamf.com/products/jamf-now/),
[custom profile limitation](https://support.jamf.com/en/articles/11030452-custom-profiles-in-jamf-now),
[2023 service-plan change](https://learn.jamf.com/r/en-US/jamf-now-documentation/2023-5).

**Fleet has a strong configuration-as-code fit.** It documents policy upload via
API/GitOps and user-scoped DDM declarations, as well as generating a starter
repository with `fleetctl new`. Its optional UI-locking GitOps mode is Premium;
that is distinct from the configuration-as-code workflow itself. Hosting or
operating Fleet is a larger scope than delivering a few privacy policies. Check
the selected release, license and user enrollment channel in a pilot.
[Configuration profiles](https://fleetdm.com/guides/custom-os-settings),
[GitOps reference](https://fleetdm.com/docs/configuration/yaml-files),
[Premium UI mode](https://fleetdm.com/guides/gitops-mode).

**Apple Business now has built-in MDM at no cost for organizations.** Its custom
configuration upload supports `.mobileconfig` files. It is worth considering for
an eligible business, but it requires organization verification; it is not an
assumed personal-account entitlement. Current verification offers several methods,
including business ID, domain validation and documents; older claims that every
applicant must have a D-U-N-S number are too narrow. Custom profile upload alone
does not establish arbitrary DDM declaration/API support.
[Apple launch announcement](https://www.apple.com/newsroom/2026/03/introducing-apple-business-a-new-all-in-one-platform-for-businesses-of-all-sizes/),
[verification](https://support.apple.com/guide/business/sign-up-and-verify-your-organization-axm402206497/web),
[custom configuration](https://support.apple.com/id-id/guide/business/axmcf4de99c4/1/web/1).

**NanoMDM is an infrastructure project rather than the simplest permission fix.**
MicroMDM v1 entered maintenance mode with best-effort fixes only through the end
of 2025; its maintainers direct development toward the Nano suite. NanoMDM focuses
on enrollment, push notifications and command delivery, leaving additional service
integration to its operator.
[Maintenance notice](https://micromdm.io/blog/micromdm-v1-maintenance-mode/),
[NanoMDM architecture](https://micromdm.io/blog/introducing-nanomdm/).

### Certificates and ongoing responsibility

A third-party service requires an APNs push certificate, with annual renewal
under the original Apple Account and certificate identity. The provider supplies
the CSR workflow. This certificate is separate from the Apple Development identity
used to sign locally built apps. A working development signing identity does not
make its owner an MDM vendor or supply an APNs push certificate.
[SimpleMDM prerequisites](https://simplemdm.pdq.com/hc/en-us/articles/9355287096091-Getting-Started-With-SimpleMDM),
[Fleet APNs renewal](https://fleetdm.com/guides/apple-mdm-setup).

Self-hosting also requires a vendor-signed CSR path, HTTPS service, enrollment
identity infrastructure and persistent service state. Apple documents the MDM
vendor signing chain and the customer upload to its Push Certificates Portal.
Using a provider's CSR-signing service avoids becoming an MDM vendor but introduces
that dependency. Assess availability before selecting a self-hosted stack.
[Apple push setup](https://developer.apple.com/documentation/devicemanagement/setting-up-push-notifications-for-your-device-management-customers).

Apple currently allows Developer Program or Enterprise Program Account Holders
to request MDM vendor signing access; access is not automatic. The independent
`mdmcert.download` CSR-signing service explicitly excludes individual use and
personal devices. Consequently, do not assume that a personal NanoMDM deployment
has an eligible certificate path just because the server software is available.
[Apple vendor certificate access](https://developer.apple.com/help/account/certificates/mdm-vendor-csr-signing-certificate),
[CSR-signing service eligibility](https://mdmcert.download/instructions).

Device Enrollment gives the management service substantial authority, including
remote erase. That makes service-account security, credential storage and
recoverable enrollment meaningful parts of operating it.
[Apple Device Enrollment](https://support.apple.com/en-mide/guide/deployment/depd1c27dfe6/1/web/1.0).

## Proposed setup with Nix

This is an implementation sequence, not an existing option or deployed service:

1. Fix persistent signing for selected source-built applications first. Preserve
   vendor-signed applications and the canonical copied paths. Verify designated
   requirements before generating managed app identities.
2. Choose a hosted trial with custom device profiles; if macOS 27 consent defaults
   are the objective, require explicit user-channel AppSettings DDM support.
   Create the provider account and APNs certificate through its onboarding UI.
3. Enroll one Mac manually through its enrollment URL and local administrator
   approval. Confirm `profiles status -type enrollment` reports user-approved MDM.
   Keep this enrollment removable for the pilot.
4. Generate policy XML/plist from typed Nix values. Give profiles stable identifiers
   and UUIDs. Keep PPPC device profiles distinct from user-channel DDM JSON.
   Reject unsupported permissions, missing receiver identities and wrong channels.
5. Export reviewed artifacts through a flake build output. Upload one narrow policy
   manually first; later use the provider API from a separate explicit deployment
   command. Keep API tokens, APNs keys and enrollment secrets out of the Nix store
   and public repository. Normal rebuilds should not enroll devices or call MDM.
6. Let Nix retain package/configuration ownership and MDM own only chosen managed
   policies. Avoid competing app update managers or duplicate preference owners.
7. Validate actual feature behavior in the GUI, then repeat after changed app builds,
   relaunch and Nix reactivation. Verify policy removal and unenrollment recovery.
   An installed profile or an acknowledged command does not prove feature access.

For this repository, the immediate choice remains persistent signing plus attended
consent. Reconsider MDM for repeatable provisioning of several Macs, centralized
policy or recovery. If learning MDM itself is an objective, a narrow hosted pilot
is proportionate; running a new self-hosted control plane is a separate project.

## Validation and limits

This follow-up reviewed primary Apple schemas, vendor documentation and repository
owners; it created no MDM account and performed no enrollment or policy delivery.
The preceding signing investigation's native observations are historical evidence,
not a fresh MDM test. Personal-account eligibility and user-channel AppSettings
behavior remain service-specific pilot questions. Some Apple Support page opens
returned HTTP 429; their indexed official text was available for the cited claims.
Prices and service capabilities are retrieval-date observations, not guarantees.
