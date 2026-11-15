# Darwin application readiness

The personal-Mac framework inventories selected application capabilities and
checks copied bundle identities. It does not install privacy grants or enroll a
Mac in device management. Apple's
[Local Network privacy guidance](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
explains the identity and user-consent requirements for local connections.

## Installation and selection

The Home Manager `macos` feature imports
[`macos.applicationCapabilities`](../../modules/home/macos/application-capabilities.nix).
It defaults on when Darwin copied applications are enabled. Selected application
modules contribute their own bundle identities and feature requirements. The
manifest is generated at `~/.config/macos/application-capabilities.json` during
normal Home Manager activation, alongside `hm-macos-readiness` in the home package
set. A combined Darwin switch remains the normal deployment path.

AeroSpace window management, LinearMouse pointer behavior, Codex local services, region OCR, Bitwarden browser integration, Zoom
voice and the selected monitor login behavior are included initially. Optional
video, screen-sharing and Signal-call features remain opt-in:

```nix
macos.applicationCapabilities.apps.zoom.features.sharing.enable = true;
macos.applicationCapabilities.apps.signal.features.voice.enable = true;
macos.applicationCapabilities.apps.teams.features.sharing.enable = true;
```

Disable an app's inventory with its `apps.<key>.enable` option, or turn off the
framework with `macos.applicationCapabilities.enable = false`. Removing a feature
from the manifest does not revoke its macOS permission or erase historical
private receipts. Unsupported managed delivery has no public configuration option.

## Read-only inspection

```sh
hm-macos-readiness --check
hm-macos-readiness --check --json
hm-macos-readiness --guide aerospace windowManagement
```

Checks run Apple's deep, strict, all-architecture signature verification and
compare signed executable identifiers, plist identities and configured vendor
teams. They neither start apps nor write receipts or caches. Bundle integrity
and matching identity do not establish Developer ID trust, notarization, or a
privacy grant. Ad-hoc signing is reported explicitly; certificate signing alone does not
establish trust.

The JSON reports application `identityStatus` separately from each feature's
`status` and `observed` authorization. `ready` on the application means its identity
checks passed. Protected feature authorization stays `unknown`: a shell helper
cannot inspect another app's grant reliably. Unsupported OS versions and invalid
identities are reported explicitly. Installed policies or past successful tests
never manufacture a current grant.

Exit codes:

| Code | Meaning |
| --- | --- |
| 0 | Inspection with no outstanding selected capabilities, successful guidance, or successful explicit evidence recording. |
| 1 | Invalid manifest, native error, identity failure, or unsafe evidence operation. |
| 2 | Valid identity inspection with selected capabilities whose current authorization remains unknown or unsupported. |

Opening UI is explicit and optional:

```sh
hm-macos-readiness --guide aerospace windowManagement --open app
hm-macos-readiness --guide aerospace windowManagement --open settings
```

The command refuses to guide approval of an app whose identity check fails.
No command edits TCC, resets permissions, broadens LAN exclusions, or restarts
apps. System Settings opens at its general application entry point rather than
relying on undocumented version-specific deep links.

## ChatGPT Local Network recovery

A copied app update can leave the running process using the previous executable
while Launch Services describes the replacement bundle. A valid signature and an
enabled Local Network switch alone do not establish that GUI-origin connections
work. Apple's [Local Network privacy guidance](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
explains responsible-app attribution and duplicate-version problems. Command
network policies are a separate layer; see [OpenAI permissions](https://learn.chatgpt.com/docs/permissions).

In the observed incident, connections recovered after the logged-in user
refreshed registration. Earlier relaunch, consent toggles and a root registration
experiment had already occurred, so this sequence does not isolate the cause or
establish registration refresh as a general privacy repair.

After an update, finish active app tasks and fully quit/reopen the canonical
copied ChatGPT application. If a real connection still reports
`localNetworkDenied`, use System Settings to turn the existing ChatGPT Local
Network entries off, close/reopen Settings, and turn those entries back on.
Then refresh the canonical registration as the logged-in Mac user:

```sh
app="$HOME/Applications/Home Manager Apps/ChatGPT.app"
codesign --verify --deep --strict --all-architectures "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
hm-macos-applications --check
```

Apple documents [targeted registration refresh](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/MDImporters/Concepts/Troubleshooting.html).
The existing `hm-macos-applications` repair command also refreshes all configured
canonical registrations; `--check` only inspects them. Registration refresh is
metadata repair, not a privacy grant or a documented reset of Local Network
state. It preserves the signed vendor bundle. Apple provides no supported
per-app reset-to-undetermined operation for this macOS permission.

Run acceptance from a task inside the reopened GUI app. Test a fresh plain TCP
connection, a Network.framework connection, and an uncached direct SSH connection
to the intended LAN endpoint. Repeat beyond two minutes, then repeat after a
normal app relaunch. A shell spawned by SSH is an exempt control, so its success
cannot substitute for the GUI test. Keep destination addresses and raw attribution
logs in private evidence storage. If the tests still fail, retain the failure;
do not record a successful feature test from the permission toggle alone.

### Guarded canonical-path migration

The Mac profile uses the vendor default, `ChatGPT.app`. Its previous-bundle list
includes `ChatGPT Managed.app`, the temporary name used during the identity
investigation. The same guarded transaction retires that former canonical path
when returning to the vendor name. The selected source remains the vendor's
original signed bundle. Launchers, capability checks, acceptance commands and
lifecycle monitoring derive their paths from the selected canonical destination.

The vendor name alone does not fix CLI application discovery. Native testing of
the unmodified selected CLI 0.163.0 failed to discover the signed bundle under
`~/Applications/Home Manager Apps`, while the identical bundle under
`~/Applications` was discovered. The Darwin CLI therefore retains its guarded
explicit-path repair. The configured wrapper supplies the selected destination;
it verifies the vendor signature and refuses a missing or invalid explicit app
instead of downloading another installation. Keep this temporary fix until the
selected upstream CLI supports that configured location and its native launcher
checks pass without the patch.

The migration addresses a candidate failure mode observed with a valid live
vendor signature: Network Extension attributed the same process to an unsigned
fallback identity, and its logs contained a rule tied to the former canonical
pathname. This establishes an identity disagreement, rather than proving that
the pathname caused it. Apple DTS describes related [Local Network state bugs](https://developer.apple.com/forums/thread/809211)
and recommends [capturing a fresh-failure sysdiagnose](https://developer.apple.com/forums/thread/814226).
A successful registration operation does not establish that these OS bugs have
been fixed.

Before activation, fully quit the app and finish its active tasks. Preflight
blocks migration while any copy is running. It verifies the vendor identity of
the selected source and previous canonical copy, and rejects unknown build
ordering, downgrades, symlinks and conflicting names. Home Manager excludes both
names from its ordinary in-place copy. The lifecycle transaction installs the
verified destination and retains the complete previous bundle in a private
`.hm-app-update-*.noindex` directory beside the copied-app directory.

Each mutation has an atomic intent journal in that recovery directory. Failures
after a mutation may have occurred preserve both complete bundles and report the
directory for inspection. Do not remove it or overwrite a running app to retry.
The transaction unregisters both the former URL and retained backup URL because
Launch Services can follow a moved bundle; `.noindex` alone does not exclude a
backup from registration. Verify canonical resolution in both root and user
contexts after activation. Reusing the selected destination on later rebuilds
does not repeat the migration.

Launch the selected app normally from Finder and run extended GUI-origin
acceptance, followed by a normal relaunch and rebuild check. Keep a failed result
if denial recurs; moving an app does not grant permission. If rollback is needed,
fully quit the candidate, preserve its complete bundle, and restore the previous
configuration and canonical registrations. File and registration recovery cannot
restore or guarantee macOS privacy/cache state or application-data compatibility.

## Record a performed GUI feature test

Run the actual operation described by `--guide`. Then record what succeeded or
failed, including a short description of the operation:

```sh
hm-macos-readiness --verify aerospace windowManagement \
  --result passed --origin gui-app \
  --evidence 'Switched windows and workspaces using AeroSpace'
```

`--verify` records an operator-reported feature test; it does not execute the
feature or independently verify that statement. A successful SSH connection or
System Settings toggle alone does not establish successful GUI behavior.

Receipts include app/feature, version, identity fingerprint, OS version/build,
time, origin and result. They live in the private state directory
`$XDG_STATE_HOME/macos-readiness` (normally `~/.local/state/macos-readiness`).
Writes use a private lock and atomic replacement; filenames encode the complete
app/feature tuple without dotted-name collisions. Interrupted writes preserve
the previous receipt. Read-only checks label malformed evidence stale and never
treat it as authorization. Bundle, OS or test-instruction changes invalidate its
observation key; generation rollback cannot restore macOS consent.

## Signing repairs and recovery

The registered [temporary package repair](../../overlays/temporary/darwin-application-signatures.nix)
preserves AeroSpace and Zoom vendor signatures by disabling destructive stripping.
Zoom's declaration also checks its vendor Team ID. The repair does not use
private signing keys or re-sign unrelated installed apps during activation.

Signal is built from source with the upstream main and inherited Electron
entitlement files. The repair signs its completed bundle after packaging, with
hardened runtime and explicit scopes for the main app and four helpers. It adds
only `com.apple.security.cs.disable-library-validation` to these upstream sets:
ad-hoc code has no shared vendor Team ID, so library validation otherwise rejects
Electron Framework and packaged native modules. Helpers retain their inherited
JIT grants without receiving the main app's camera or microphone entitlements.
This exception permits loading libraries without a common signing team; it does
not provide vendor trust. The repair rejects a changed helper layout for review.
It does not add unsigned-executable-memory or debugger entitlements.

Sandbox-compatible package checks compare AeroSpace against its original signed
bundle, compare Zoom against its unpacked vendor payload, and require Signal
signing to be byte-idempotent. They retain strict
Nix sandboxing. Apple's authoritative check runs outside the build sandbox:

```sh
codesign --verify --deep --strict --all-architectures \
  "$HOME/Applications/Home Manager Apps/AeroSpace.app"
codesign --verify --deep --strict --all-architectures \
  "$HOME/Applications/Home Manager Apps/Signal.app"
hm-macos-applications --check
```

The initial attended rollout used a separate Nix profile at
`~/.local/state/nix/profiles/macos-readiness`, so its command is also available as
`~/.local/state/nix/profiles/macos-readiness/bin/hm-macos-readiness`. Only the two
verified app copies were replaced; their previous bundles were retained under
`~/.local/state/macos-application-repairs/` with a recovery journal. This avoided
activating unrelated working configuration changes. Subsequent attended full
activation installs the framework through the normal Darwin and Home Manager
generations. An older Home Manager generation can restore older app packages;
use the updated configuration for subsequent switches. A trial app replacement
alone is not a new system or Home Manager generation.

Restore a retained bundle only after quitting the corresponding application and
reviewing its journal. Keep the current bundle separately, restore the selected
previous copy to the canonical path, and verify registration again. A retained
old signature failure remains a failure; recovery restores the previous state,
not a promise of valid signing. Do not overwrite app preferences, pairing keys,
Keychain items or privacy databases as part of bundle recovery.

## Validation record

On macOS 27.0.1 arm64, both repaired outputs and installed copies passed Apple's
strict deep verification. Attended testing confirmed AeroSpace window shortcuts
and a Moonlight stream after replacement; private evidence receipts record both.
The running AeroSpace server also returned five window IDs through its IPC CLI.
Canonical registration remained consistent for all 30 applications. A subsequent
rebuild/replacement retained AeroSpace's signature and historical observation,
while Moonlight's changed ad-hoc identity made its earlier observation stale.
After fully quitting/reopening the final Moonlight build, attended streaming
passed again and a fresh receipt was recorded.

The generated selected-profile manifest contains ten applications. The remaining
Signal and Zoom failures reproduced in both the older installed bundles and the
new pinned packages. Zoom's repaired package preserves the vendor-signed bundle,
including its Team ID and hardened runtime. Signal's completed source-built
bundle passes strict verification with the scoped entitlements described above.
A control using upstream entitlements without the library-validation exception
failed to load Electron Framework; the narrow exception cleared that failure.
Signal's upstream entitlement files contain comments before their XML declaration;
the signer normalizes that preamble, covered by the regression fixture.

Native acceptance checks inspect the main app and all four helpers, execute JIT
and all five packaged native modules, and require modified disposable bundles to
fail verification. Restoring original metadata makes the positive control pass
again; tampering with a nested Signal helper is also rejected. Disposable GUI
launches exercise normal GPU and renderer startup without attaching an account.
Attended checks confirmed the final installed Signal and Zoom builds work.
The full Darwin configuration then built and activated successfully, including
its integrated Home Manager generation. Post-activation checks passed for all
ten inventoried identities and all 30 canonical registrations; the installed
copies also passed the native runtime and tamper controls. AeroSpace IPC remained
responsive. The previous system generation and app recovery bundles were retained.
A fresh Zoom audio-test receipt records the attended result while leaving current
macOS authorization unknown.

A coordinated login repair places user secret phases in the GUI launchd domain
and makes the local proxy retry when its protected environment file appears.
Disposable native jobs reproduce both failures with the earlier policies and pass
with the generated replacements. After full activation, both configured GUI
secret jobs exit successfully and the proxy runs. A fresh invocation of the root
startup job also succeeds. These checks exercise login policies without logging
out or rebooting the working session.

A subsequent ChatGPT Local Network investigation reproduced denied GUI-origin
TCP, Network.framework and uncached SSH connections despite valid signing and
enabled consent. After the recovery sequence above, all 60 checks passed across
two runs, each containing five rounds over 120 seconds against two selected LAN
endpoints. The second run followed a full ChatGPT quit/reopen. Kernel process
inspection confirmed each test interpreter was attributed to its distinct,
current canonical ChatGPT process. Plain TCP, Network.framework and uncached
strict SSH all passed in every round. The vendor signature remained intact and
a current feature-test receipt records the successful relaunch test.

The combined native macOS suite passed 61 tests, including entitlement-scope
and helper-layout regression coverage. Portable behavior tests cover
identity failures, plist errors, explicit UI
opening, malformed manifests/receipts, receipt staleness, interruptions,
concurrent processes and dotted identifiers. Native Nix contract tests cover
selection, opt-outs, duplicate identities and case-insensitive paths, unsupported
options, platform gating, and declaration ownership. Full Darwin and desktop system derivations also evaluated on the Mac; no desktop
closure was built there. Native evaluation first reproduced, then cleared an
existing launcher-expression failure: Darwin rejects an empty regex alternative, so
optional launch executables use `(Contents/[^.].*)?`.

Revoking production permissions and rebooting during active work were not part
of the attended rollout. The remaining denial, revocation, login/reboot, broader
update and generation-rollback acceptance matrix should
run in a disposable account or VM. Unit tests and signature checks do not stand
in for those native lifecycle tests.

## Protecting future ChatGPT updates

ChatGPT uses `macos.applications.protectedApps.codex`. Home Manager excludes
that bundle from its ordinary in-place rsync. A revision-guarded
[Home Manager adapter](../../overlays/temporary/home-manager-protected-apps.nix)
adds only this exclusion; an unfamiliar Home Manager revision requires review.
The [lifecycle helper](../../modules/home/macos/application_lifecycle.py) owns the
protected copy:

- Before Darwin activation and Home Manager's write boundary, verify the selected
  source and installed vendor signatures, bundle identity, build and Mach-O UUIDs.
- Compare each live process's loaded UUID and kernel signing hash with the installed image. An unknown
  native process capability fails closed. A running app with a different selected
  build blocks activation; a matching app is left untouched during a no-op rebuild.
- Refuse silent downgrades. Quit the app before deploying an upgrade and advance
  the Nix selection if the installed build is newer than the pin.
- Copy into a private staging directory on the same volume, verify it, repeat
  preflight, then atomically exchange complete directories. Keep the previous
  complete bundle in the reported `.hm-app-update-*.noindex` transaction directory.
  Review and remove retained backups explicitly when no longer needed.

Live signing hashes also catch sealed resource or framework changes when the main
UUID stays unchanged. Disk signatures are inspected for every architecture,
including Rosetta slices. A launch can race the final check and exchange. Atomic exchange prevents partial
bundle contents; it cannot prevent a process from retaining the previous image.
The GUI launch agent observes workspace lifecycle, filesystem and wake events,
then checks identity and records private health results. Activation refreshes
verified canonical registration in root and logged-in user contexts, in that
order. A system launchd job also watches the monitor's status directory. Each
new process incarnation triggers the same verified refresh; a root-owned ledger
suppresses repeated registration for unchanged state. The status directory is
only a wakeup signal: the privileged helper queries live processes itself and
independently verifies configured bundles against their selected Nix sources.
Identical observations do not rewrite status or trigger a registration loop.
Launchd retries failed inspections or registrations at most once every 30 seconds;
successful checks remain dormant until an event. Inspect failures with
`launchctl print system/org.nixos.macos-application-registry` and the root job's
logs under `/var/log/macos-application-registry{,-errors}.log`.
It does not quit apps. A mismatch requires a normal full Quit/reopen.
There is no polling timer. Native callbacks subscribe before the initial scan;
coalesced events trigger a full scan, and overlapping checks are serialized.

```sh
hm-macos-applications --check
hm-macos-app-lifecycle --mode check
hm-macos-app-lifecycle --mode preflight
```

The lifecycle checks are read-only. Install, explicit user refresh and observation-result writes use a
private lock and reject redirected state directories or locks. The monitor keeps
`~/.local/state/macos-applications/lifecycle/status.json`, logs through launchd,
and attempts one notification when a new failure appears. Notification delivery
is best effort; the status file and command exit code remain authoritative.
Registration refresh is metadata maintenance, not a supported privacy reset.

The selected Mac declares `[features] in_app_updates = false` in the root-owned
`/etc/codex/requirements.toml`. This is the supported desktop update policy,
separate from CLI update checks. After fully quitting/reopening ChatGPT, confirm
Settings → General shows **In-app updates: Managed**. A file on disk alone does
not prove that a particular app release applied it. Higher-priority organization
or MDM policies can override local requirements. See OpenAI's
[update policy](https://learn.chatgpt.com/docs/enterprise/manage-app-updates) and
[managed configuration precedence](https://learn.chatgpt.com/docs/enterprise/managed-configuration).
Nix now owns timely app and security upgrades.

After an upgrade, macOS update, or identity warning, run this from the canonical
ChatGPT GUI command runner, substituting an intended reachable LAN service:

```sh
hm-macos-network-test --endpoint '<LAN_HOST>:<PORT>'
```

The packaged test checks plain TCP and Network.framework in five rounds over
120 seconds and validates application identity before and after. It rejects an
SSH/Terminal ancestry and loopback/public endpoints. Its ancestry report can be
independently checked with privileged `launchctl procinfo <TEST_PID>`; ancestry
alone is not an independent kernel responsibility query. It prints evidence to
the invoking chat without writing private endpoint details into the repository.
Repeat after a normal app relaunch and exercise the actual intended service
protocol, such as an uncached strict SSH connection. Record the result with
`hm-macos-readiness --verify codex localServices --result passed --origin gui-app
--evidence '<reviewed result>'`. Existing receipts become stale when app identity,
OS build or instructions change. Current authorization remains unknown even after
a successful test. There is no supported check that guarantees a future macOS
Local Network decision before an actual GUI-origin connection.

The durable update controls passed 91 native Mac tests, including real signed
bundles whose sealed resources change while their main Mach-O UUID stays the same.
The kernel signing-hash check rejects the resulting live/disk mismatch. Tests
also cover staging failure, process reuse, running upgrades, no-op rebuilds,
downgrades, the final launch race, atomic exchange, unsafe lock paths, endpoint
pinning, origin rejection, process-incarnation deduplication, retryable registration
failures, AppKit/FSEvents callbacks for background apps, and the installed launchd
policy retrying failure and remaining dormant after success.
The focused Nix contract and Home Manager revision guard passed. Full Darwin
activation left the running ChatGPT executable's inode, modification time and
size unchanged, and all ten inventoried identities and 30 registrations passed.

The deployed controls also passed 80 GUI-origin connectivity checks: two intended
LAN targets, two Python runtimes, plain TCP and Network.framework, in five rounds
over two minutes after a full ChatGPT relaunch and again after reactivating the
same Nix configuration. Kernel responsibility identified the canonical GUI app.
The system job automatically refreshed the new process's verified registration;
no manual refresh was used after that relaunch. Reactivation retained the same
running process and unchanged executable bytes. The job remained idle with a
successful exit after handling events, and the temporary diagnostic bridge was
closed after verification. These are observed results for the tested app and OS,
not a guarantee of future privacy decisions.
