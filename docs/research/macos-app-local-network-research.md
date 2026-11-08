# macOS app local-network access: prevention and recovery

Reviewed: 2026-10-15. Scope: macOS local-network privacy, app registration,
and Codex command-network controls; configuration baseline
`21237bdb8974bda44d4a8c591b50e542dd7dc6c3`.

## Answer

Keep Nix configuration unchanged. A later diagnostic reproduced an app-origin
Local Network denial while the same probe passed over SSH. This identifies the
enforcement boundary; it does not establish a packaging defect that
recursive helper registration, an activation-time app restart, a subnet
exception, or relaxed Codex permissions would fix. Preserve the existing
registration of the canonical copied application.

## Findings and sources

### Incident observations and current checks

SSH to a numeric guest address worked through the host's SSH service while the
desktop app's runner reported no route. The main app appeared allowed in Local
Network settings. Refreshing nested-helper registrations removed lookup errors;
the next app-runner SSH attempt still failed. Later, the GUI was found closed
and launched afresh. A successful remote-runner attempt was attributed to the
SSH service, so it did not test desktop-app access. The operator subsequently
reported successful SSH from the desktop app runner.

Read-only inspection during this review confirmed that the currently installed main GUI
and nested CLI bundles both passed `codesign --verify --strict`. That establishes
current signature validity, not the identity or validity of every process during
the failure. Earlier unrelated signature failures do not override this result.

The existing canonical-registration check also passed for all 30
applications. A separate CLI inspection reported `network_proxy` disabled and
`danger-full-access`; this did not independently capture the failing GUI task's
effective policy.

These observations establish eventual recovery. They do not establish a
controlled restart of the failing process, or separate registration changes,
privacy state, app runtime, and concurrent network changes. A stale permission
cache remains a hypothesis.

### Recurrence review on 2026-10-15

During a later report, the host was remote over WireGuard. Its configured LAN
multicast name did not resolve from the desktop, and initial SSH attempts to the
VPN peer address timed out before authentication. UniFi inspection confirmed the
configured peer, VPN zone, and an existing source/destination-specific TCP port
22 allow rule with return traffic. That rule had a one-time maintenance schedule;
its existence does not establish permanent remote-management access. No gateway
settings were changed during this review.

The peer subsequently appeared connected, and desktop-to-host SSH succeeded
without an intervention by this reviewer. Host-to-guest SSH returned the expected
hostname, and the operator's requested runner retest also returned that hostname.
The GUI and VM retained their previously observed process IDs. Both bundle
signature checks passed again. These results establish current reachability,
without proving what changed between failed and successful attempts.

The host's network helper repeatedly logged that local-network access was allowed
by preference but a prompt had been received, then cleared cached executable
UUIDs and restarted its session. This is direct evidence of permission-cache
handling during the recurrence window. It does not establish which command
triggered each event or prove that cache handling caused or repaired SSH failure.
The distinction between VPN reachability and app-origin guest access remains
essential; a gateway policy change cannot be justified from these logs alone.

The gateway flow history later supplied separate evidence: some desktop-to-peer
SSH attempts were blocked and others allowed. The existing narrow maintenance
rule was also found paused. After explicit operator approval, it was renamed,
saved with an Always schedule, and enabled, retaining its single desktop source,
single VPN peer destination, TCP port 22, and return-traffic handling. Reloading
the policy editor confirmed the saved scope, schedule, and enabled state.
Subsequent inbound SSH attempts still timed out, so the policy change does not
establish restored host access or remediation of the app-origin incident.
An outbound diagnostic tunnel was requested to inspect the remaining failure
without expanding the gateway rule.

That tunnel subsequently established authenticated access. The host's SSH daemon
listened on wildcard port 22, its application firewall allowed SSH, and its route
back to the desktop selected WireGuard. A bounded VPN-interface capture during a
failed direct attempt saw no matching connection-initiation packets. A matching
gateway flow explicitly reported an intrusion-prevention block under signature
2003068, `ET SCAN Potential SSH Scan OUTBOUND`, with packets sent and none
received. This establishes a gateway IPS cause for those desktop-to-host attempts;
it does not explain app-origin access to the guest's host-only network.

After separate operator approval, a suppression was applied for that one
signature and the single host VPN IP. The saved entry matches both traffic
directions for that IP; it is not restricted to the desktop/host address pair.
The firewall remains independently restricted to the single wired desktop,
single VPN peer, and TCP port 22. All other IPS signatures remain enabled.
UniFi documents signature suppression separately from firewall allow rules and
whole-IP detection exclusions. [UniFi IDS/IPS documentation](https://help.ui.com/hc/en-us/articles/360006893234-UniFi-Gateway-Intrusion-Detection-and-Prevention-IDS-IPS)

Six fresh desktop-to-host SSH connections passed after application, and
host-to-guest SSH again returned the expected hostname. Direct host access had
also succeeded once immediately before suppression, so these checks are not a
controlled failing/passing demonstration of its effect. The known IPS detection
and the deliberately scoped exception support retaining it for the approved
management traffic. Main-app and bundled-CLI signatures passed again. Kernel
process inspection attributed both GUI-spawned backends to the running GUI;
their backend processes were not sandboxed. This does not prove a particular
child command's effective policy or substitute for a failing GUI-runner test.

### Confirmed GUI-origin Local Network denial

A temporary diagnostic was subsequently invoked through the Mac's Codex command
runner. It recorded the GUI-owned backend as its parent and the running GUI as
its responsible process. Network.framework reported an unsatisfied path with
`localNetworkDenied`; SSH exited 255, and a source-bound TCP connection returned
`EHOSTUNREACH`. The identical probe invoked through the host's SSH service
reported Network.framework ready, successful SSH, and a successful bound TCP
connection. This directly establishes Local Network enforcement in the GUI
context, independently of the separate gateway IPS incident.

Read-only inspection found an allowed main-app record, older path/name records,
and helper/CLI records with no user choice. Those internal records do not prove
which visible entry repairs the denial. The executable UUID comparison found no
collision with the other canonical or top-level installed apps, and the canonical
registration check still passed. No app, VM, or privacy service was restarted.

On the installed macOS 27.0.1, Apple documents no supported Local Network state
reset. App-specific removal/reset controls start in 27.2. The next step is to
identify the exact relevant System Settings entry and test its grant through the
same GUI-origin probe, rather than edit private permission databases or broaden
system policy. [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

### Vendor behavior relevant to the hypotheses

Apple's TN3179 states that macOS exempts command-line tools launched over SSH
and their children. App-spawned helpers are attributed to responsible app code.
Apple also documents code-signing and executable UUID considerations. Apple documents
multiple-version settings anomalies (FB15568200), short-lived-process alert
failures (FB16131937), and no MDM control over grants. These are vendor
limitations, not an incident diagnosis. [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

`NSLocalNetworkUsageDescription` supplies the explanation shown when requesting
access; Apple recommends it for apps using local networking directly or
indirectly. Its documentation does not promise that adding it grants access or
repairs an existing denial. Inspect the shipped bundle before alleging missing
metadata. [Apple property reference](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription)

For legacy launchd agents outside `SMAppService`, TN3179 directs developers to
`AssociatedBundleIdentifiers`. [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
Apple's helper migration guide also requires matching Team Identifiers and a
Launch Services registration for the associated app. That guidance concerns
attribution for these service installations; it is not a general requirement to
register every nested app helper. [Apple helper migration guide](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)

Launch Services registration records an app and its document/URL claims.
The registration API does not document a privacy grant or permission-cache
repair. Inferring either from a successful helper lookup is unsupported.
[Apple LSRegisterURL reference](https://developer.apple.com/documentation/coreservices/1446350-lsregisterurl)

Codex has a separate command-network control layer. Current official documentation
distinguishes network enablement from proxy filtering. With networking enabled
and the proxy disabled, commands have direct network access; with the proxy
active, domain rules and a local/private-network guard apply. Exact local IP
literals can be allowlisted; resolving allowed hostnames to private addresses
requires the documented additional setting. Thus a diagnostic label such as
“network sandbox enabled” does not establish the effective policy or prove that
it denied this connection. Verify the actual execution surface, active profile,
proxy state, managed requirements, and denial evidence before changing it.
[Official OpenAI permissions documentation](https://learn.chatgpt.com/docs/permissions#network-permissions)

## Evaluated alternatives

| Alternative | Decision and evidence needed |
| --- | --- |
| Keep canonical app registration | Retain existing behavior. No demonstrated registration regression justifies extending it. |
| Recursively register nested helpers at activation | Do not add. Lookup errors disappeared without immediate SSH recovery. Require a reproducible failing app-origin connection that registration alone repairs, with unchanged process identity and policy. |
| Automatically restart the app during activation | Do not add. Fresh launch preceded reported recovery, but the failing process was not observed undergoing a controlled restart. Require a repeatable runtime-lifecycle mechanism and a deliberate lifecycle policy before automating disruption. |
| Patch bundle metadata or re-sign executables | Inspect first. Require evidence of missing metadata, invalid or changed identity, or UUID collision in the running shipped artifact, plus an upstream-compatible packaging remedy. |
| Add `AssociatedBundleIdentifiers` | Only if a relevant legacy launchd agent and incorrect responsibility are demonstrated. A spawned helper alone does not establish that prerequisite. |
| Change per-app Local Network access | Appropriate only after identifying the actual responsible app and its denied grant. The reported main-app grant alone cannot validate another identity. |
| Relax Codex network controls | Do not add. Require effective-policy and proxy-denial evidence from the failing command's execution context. |
| Add a subnet exception | Do not add for this incident. It would be a separate decision to broaden system policy rather than a demonstrated repair. |

Since macOS 15.5, `AllowedEthernetLocalNetworkAddresses` and
`AllowedWiFiLocalNetworkAddresses` in `com.apple.network.local-network` accept
CIDR arrays for the named interface types. These system-wide exceptions permit
every app and require a reboot. Guest virtual-interface applicability remains
unverified. [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

## Validation and limits

This review fetched current primary documentation, including Apple's Markdown
endpoints. TN3179's latest listed revision is 2026-10-06. Read-only checks on the
Mac verified the main app and bundled CLI signatures with
`codesign --verify --strict`, verified 30 canonical registrations with
`hm-macos-applications --check`, and returned the guest hostname over SSH through
the host's SSH service. That last check does not test GUI-origin networking.
The successful GUI-runner result was reported by the operator.

The initial documentation review made no runtime or configuration changes.
The later gateway rule and IPS changes are recorded separately above. No Mac
build, activation, permission reset, app or VM restart, or controlled app-origin
failure/recovery experiment was performed during these reviews. The earlier
helper refresh and fresh launch are incident history, not validation of a
proposed declarative fix.

Before a code change, capture a recurrence in the desktop app's own runner:

1. Record OS/app versions, the actual running bundle, code-signing identity,
   executable UUID, process ancestry and kernel responsibility, while keeping raw
   captures private. Determine whether multiple app installations participate.
2. Compare one bounded app-origin SSH attempt with a contemporaneous host SSH
   attempt to the same guest; record route/interface and effective Codex policy.
   Remote execution validates its own origin, not the desktop app.
3. Obtain a specific privacy-denial signal where possible. TN3179 describes
   `NWConnection` with `localNetworkDenied`; a generic no-route error is
   insufficient by itself. [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
4. Change one proposed cause at a time and repeat the app-origin test. Document
   process continuity and intervening events. A separately launched test program
   may have different responsibility and cannot automatically validate the
   failing app's grant.

## Implication for this repository

The existing [application reconciler](../../modules/home/macos/application_registry.py)
registers the canonical app without recursively registering helpers. The
[Home Manager integration](../../modules/home/macos/applications.nix) uses copied
applications; the [packaging documentation](../../pkgs/pkgs/by-name/ch/chatgpt-latest/README.md)
explains preservation of the vendor-signed macOS bundle. Current checks do not
establish a defect in those choices.

Retain current Nix configuration. The GUI-origin denial is confirmed; its
permission-state or identity repair remains unverified. Use the recorded probe
to validate that repair before proposing a packaging or integration change.
