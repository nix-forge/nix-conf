# Resource waits and repeated work

Reviewed: 2026-10-10. Scope: project-owned waiting code in the root repository,
package recipes, homelab modules, framework, and secret runtime. The installed
Python runtime is 3.14.7. This review distinguishes idle spinning, repeated
probes with delays, blocking event waits, and deliberate test timing.

## Current policy and changes

Use notifications when the producer provides them. Register before the initial
snapshot, recheck after notification, and keep one overall deadline. A loop over
blocking input or finite work does not busy-wait. A sleep suspends its thread,
but recurring status probes still incur wakeups and delayed observation.
[Python select](https://docs.python.org/3/library/select.html),
[Python time](https://docs.python.org/3/library/time.html#time.sleep),
[condition variables](https://docs.python.org/3/library/threading.html#condition-objects).

| Component                                              | Change in this review                                                                                                                                                                                                               |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Development VM reverse tunnel                          | Removed the preliminary netcat probe. SSH establishes the remote listener independently and connects to the local target when forwarded traffic arrives.                                                                            |
| BookOrbit native PostgreSQL                            | Replaced pg_isready probes with Type=notify and a five-minute startup timeout. The selected Linux PostgreSQL package links systemd support.                                                                                         |
| Native BookOrbit metadata initialization               | Removed repeated schema queries. Existing dependencies already require the completed migration before application and metadata startup.                                                                                             |
| Windows VM finalization                                | Register a libvirt lifecycle callback before querying state or requesting graceful shutdown. A native event-loop timer bounds waiting; failure preserves the installer definition.                                                  |
| Isolated compositor runner                             | Subscribe to filesystem changes, then check readiness and block on a condition variable. Ignore read events to prevent the probe from waking itself. Create the test output once per instance.                                      |
| Child supervision                                      | Use Linux pidfd notifications for compositor children, application recovery hook deadlines, and storage health cleanup. Python 3.14 timed Popen.wait uses repeated nonblocking waitpid calls.                                       |
| Evidence verification and secure-file release fixtures | Use blocking pipe and child waits with a deadline timer. Verification owns and terminates its process group; each release fixture shares its deadline across readiness, input and exit. Cancel and join the timer before returning. |
| Worktree session test                                  | Replace marker-file polling with a pipe handshake.                                                                                                                                                                                  |
| Shuffle authentication                                 | Honor Retry-After seconds and HTTP dates, reject excessive delays, keep a positive floor and cap attempts under a monotonic retry budget. Authentication failures and reconciliation writes are not retried.                        |

The reverse-forward destination is opened only for an incoming forwarded
connection. ExitOnForwardFailure covers listener setup, not the destination's
availability. This removes a redundant readiness gate without changing the
forwarding protocol.
[OpenSSH ssh(1)](https://man.openbsd.org/ssh.1),
[OpenSSH ssh_config(5)](https://man.openbsd.org/ssh_config.5#ExitOnForwardFailure).

PostgreSQL documents notify startup for builds with systemd support and cautions
that recovery can exceed the ordinary service startup timeout. Application
migration remains a separate ordered operation. An unrelated application cannot
be made ready merely by assigning Type=notify.
[PostgreSQL 18 startup](https://www.postgresql.org/docs/18/server-start.html),
[systemd service types](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html#Type=).

Launchd's SuccessfulExit policy and ThrottleInterval provide restart ownership.
Libvirt provides registered domain lifecycle callbacks and an event loop with
native timeout events. Python selectors can wait on Linux pidfds; untimed wait
then reaps a child whose exit notification has arrived.
[Apple launchd.plist contract](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchd.plist.5),
[libvirt lifecycle callbacks](https://libvirt.org/html/libvirt-libvirt-domain.html#virConnectDomainEventRegisterAny),
[libvirt event loop](https://libvirt.org/html/libvirt-libvirt-event.html#virEventRunDefaultImpl),
[Python 3.14 subprocess](https://docs.python.org/3.14/library/subprocess.html#subprocess.Popen.wait).

A deadline timer also allows synchronous verification to retain blocking child
waits. Cancellation alone does not stop a timer callback that has already begun;
joining the timer completes that callback before its owner returns. The release
fixture passed against a cached native macOS helper, and focused evidence tests
covered timeout cleanup and successful and failed receipts. Those results do not
replace the pending package and system builds.
[Python timer objects](https://docs.python.org/3.14/library/threading.html#timer-objects).

HTTP backoff remains appropriate when the server supplies no readiness event.
Retry-After specifies seconds or an HTTP date; a server minimum longer than the
remaining budget stops the retry rather than being shortened. Missing or malformed
hints use the service's positive fallback. Retries have one owner and must not
blindly repeat mutations.
[RFC 9110 Retry-After](https://www.rfc-editor.org/rfc/rfc9110.html#section-10.2.3),
[RFC 6585 HTTP 429](https://www.rfc-editor.org/rfc/rfc6585.html#section-4),
[AWS retry guidance](https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/).

## Current validation and limits

Focused Linux tests cover notification races, idle waits, child deadlines,
worktree ownership, retry hints, recovery cancellation and lifecycle cleanup.
The libvirt test driver delivered a real lifecycle event with its supported
shutdown request substituted for the QEMU-specific agent and ACPI flags. The
unadapted driver rejected those flags, so that test is not Windows guest evidence.
Run the compositor helper through `nix develop .#tests --command python3` so its
filesystem observer dependency comes from the pinned test environment.
Generated proxy tests check failure propagation and tunnel startup without a
local proxy. Native Darwin launchd behavior and Windows shutdown remain untested.
The sandboxed Linux Python suite passed all 562 selected cases; 53 daemon or
artifact cases were deliberately deselected by the existing check policy.
Generated proxy/tunnel checks, native BookOrbit configuration checks, formatting,
focused type checks, documentation lint, and the reviewed patch's secret scan
passed. Darwin configuration evaluation passed; it was not built or activated.

A before/after syscall trace of a 200 ms recovery hook recorded 11 WNOHANG
waitpid probes before the change, and one pidfd creation and blocking epoll wait
with no WNOHANG probes afterward. This measures that hook's wait strategy, not
whole-system power use.

The desktop was built and activated. PostgreSQL reached notify readiness,
BookOrbit and metadata initialization succeeded, and artwork, storage pressure,
shuffle configuration and hourly Git maintenance completed successfully. No
system or user units remained failed. Cold-boot behavior was not tested.

Live verification also exposed a separate artwork refresh crash during Go/cgo
thread creation under the unit's 16-task cap. The corrected unit allows 64 tasks
and sets GOMAXPROCS=2; its retry completed successfully with a 75.6 MB memory peak.
GOMAXPROCS bounds simultaneous Go execution, rather than the total OS thread
count, so the thread cap is a separate limit.
[Go runtime GOMAXPROCS](https://pkg.go.dev/runtime#GOMAXPROCS).

Bounded HTTP readiness retries remain for third-party applications without
notification interfaces, including qBittorrent connection refusal. Container
schema initialization retains its bounded probe because migration runs inside
the container. Windows guest provisioning, Launch Services confirmation, manual
GUI probes, and some test fixture readiness checks retain bounded observations.
Explicit timing in input and timeout tests and rate limiting in metadata clients
are deliberate delays. Blocking cgroup, D-Bus, pipe, Rust condition-variable, and
netlink readers remain intact. This audit does not establish that all upstream
packages or standard-library subprocess paths are free of internal polling.

## Language-source follow-up

Source review: 2026-10-11. Maintained readiness programs and their fixtures now
live in language files, so source lint and formatting cover the extracted code.
The following implementation changes still require their native regression
checks before deployment.

| Component                           | Notification and ownership                                                                                                                                                                                      |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Container BookOrbit migrations      | Install the PostgreSQL DDL event trigger before application startup. LISTEN precedes the schema snapshot; check notifications already buffered by query execution before blocking on the connection descriptor. |
| Isolated PostgreSQL validation      | Observe the owned server's final startup log, perform one protocol-ready check, and use asynchronous child completion for cleanup.                                                                              |
| Wardrowbe queue smoke check         | Observe Valkey's ready log, start the explicitly enqueued ARQ job, await the worker tasks, then inspect the terminal result once.                                                                               |
| macOS default browser               | Await NSWorkspace's completion callback for each URL scheme and retain one final verification.                                                                                                                  |
| Windows management address          | Register NetworkAddressChanged before reading the adapter state. Wait-Event blocks between changes under a Stopwatch deadline.                                                                                  |
| Feishin artwork                     | The player owner reports completed IPC startup. Observe mpv properties and file-loaded events instead of repeated requests. Generation ownership prevents an old child exit from invalidating a replacement.    |
| MetaBrainz extension startup        | Subscribe to Spicetify's replayable webpack-loaded event. Register once and read independently initialized URI and lookup APIs at menu interaction time.                                                        |
| Hyprland fixture readiness          | Connect to the compositor notification socket before the initial focus, layer or mapped-window snapshot. Read state after events and use one deadline, including stream disconnection cleanup.                  |
| Native workload and locker fixtures | FIFO, filesystem, pidfd and D-Bus notifications replace marker and child-status probes. The workload VM check runs the generated runner and memory policy in an isolated user manager.                          |

PostgreSQL delivers NOTIFY after commit, and LISTEN must commit before taking
the initial snapshot. Psycopg can receive a notification during another query,
so socket readiness alone does not account for its buffered notification queue.
The schema regression covers unrelated DDL, uncommitted DDL, an existing schema,
and a notification consumed while returning an older snapshot.
[PostgreSQL LISTEN](https://www.postgresql.org/docs/18/sql-listen.html),
[PostgreSQL NOTIFY](https://www.postgresql.org/docs/18/sql-notify.html),
[Psycopg asynchronous notifications](https://www.psycopg.org/docs/advanced.html#asynchronous-notifications).

NSWorkspace completes its asynchronous browser-selection operation after any
required consent. PowerShell can retain registered object events in its queue.
A Unix socket inode indicates bind, not listen, so the mpv observer relies on
its owner's completed IPC startup before connecting. mpv supplies property
observations and file-loaded events over that connection.
[NSWorkspace browser completion](<https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenurlswithscheme:completion:)>),
[PowerShell object events](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/register-objectevent),
[mpv IPC protocol](https://github.com/mpv-player/mpv/blob/master/DOCS/man/ipc.rst).

Hyprland emits active-window, window-map and layer-map changes through its
notification socket. The observer subscribes before reading state and retains
notifications that arrive during a snapshot. Snapshot commands share the remaining
deadline through an asynchronous child observer; a stalled command is killed,
drained and reaped without timed process-status polling. Its regressions cover
that race, idle deadlines, stalled commands and producer disconnection. The
ClamAV offline fixture uses a FIFO completion token for its controllable updater.
[Hyprland IPC events](https://wiki.hypr.land/IPC/).

Spicetify's webpack event replays for a late subscriber. Its URI and CosmosAsync
APIs finish independently, so the extension reads them when the user selects or
looks up a track. Behavior tests cover delayed registration, event replay, missing
capabilities and capabilities supplied later.
[Spicetify event implementation](https://github.com/spicetify/cli/blob/v2.45.1/src/jsHelper/spicetifyWrapper/events.js),
[Spicetify platform initialization](https://github.com/spicetify/cli/blob/v2.45.1/src/jsHelper/spicetifyWrapper/platform.js).

Static Python and TypeScript checks passed for these source changes. The Swift
helper compiled with Swift 6 without executing browser selection. These results
do not establish Windows guest behavior, live macOS consent, or completion of
the new Linux VM and PostgreSQL checks. Upstream NixOS driver readiness helpers
and bounded remote protocol retries remain separate from the project-owned
notification waits.

## Earlier review

Previous review: 2026-09-12. Scope: root-owned scripts, service timers, generated shell
templates, Windows bootstrap code, and runtime helpers in the three submodules.

## Changes

| Component                                                                                  | Previous work                                                                                     | Replacement                                                                                                                                                          |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [Bluetooth startup policy](../../modules/nixos/hardware/scripts/disable_bluetooth_pairing.py) | Up to 100 separate property probes per adapter, spaced 100 ms apart                               | One connection subscribes to adapter-added signals before taking an ObjectManager snapshot. It sets pairing policy once per adapter and bounds the entire operation. |
| [Workload queue](../../homes/desktop/local/wait_workstation_cgroup.py)                        | A systemd query and sleep every 200 ms after the main command exits                               | Blocking cgroup populated notifications retain the queue until descendants finish.                                                                                   |
| MiniDV capture, since retired                                                              | A sysfs scan and several subprocesses each second; repeated child-exit probes during cancellation | A udev subscription, child pidfd, and signal descriptor shared one blocking selector. Deadlines applied only during shutdown escalation.                             |
| MiniDV finalization, since retired                                                         | Two identical ffprobe invocations                                                                 | One stream snapshot supplied both codec and audio checks.                                                                                                            |
| Karakeep launchd wrapper                                                                   | A Compose stack kept a Linux VM and three containers alive on macOS                               | Removed. The reusable homelab module now runs the source-built Nixpkgs package, Meilisearch and Chromium as bounded NixOS services.                                  |
| [nix-seal subprocesses](../../nix-seal/crates/nix-seal-runtime/src/child.rs)                  | Four child-status loops waking every 10 to 25 ms                                                  | One blocking observer per active child, with condition-variable deadlines and serialized cancellation/reaping. No dependency was added.                              |
| [Git privacy inspection](../../modules/home/dev/scripts/git_privacy_hook.py)                  | Full-buffer lowercasing for every blocked pattern                                                 | Normalize once per chunk, retaining case-insensitive matching.                                                                                                       |

BlueZ's ObjectManager supports discovery through a snapshot and subsequent
signals. Subscribing before the snapshot closes the registration race.
[BlueZ API guide](https://www.bluez.org/bluez-5-api-introduction-and-porting-guide/),
[D-Bus ObjectManager contract](https://dbus.freedesktop.org/doc/dbus-specification.html#standard-interfaces-objectmanager).

Linux cgroup notifications describe whether any descendants remain. The retired
MiniDV capture used udev's selectable monitor and a pidfd for its own child.
The Rust observer uses `waitid` with `WNOWAIT` so normal observation does not
release the PID before cancellation has finished. Reported loss of child
ownership fails without signalling that numeric PID.
[Cgroup notifications](https://docs.kernel.org/admin-guide/cgroup-v2.html#un-populated-notification),
[pyudev monitor API](https://pyudev.readthedocs.io/en/latest/api/pyudev.html#pyudev.Monitor),
[rustix waitid](https://docs.rs/rustix/latest/rustix/process/fn.waitid.html).

## Earlier retained waits

A bounded retry still deserves review. These retained waits have different
conditions or validation requirements from the notification replacements above.

| Location                                               | Retained behavior and reason                                                                                                                                                                          |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Windows VM baseline checks                             | Read guest provisioning status every five seconds under an overall deadline. The current guest protocol provides a file read, not a completion notification.                                          |
| Windows VM shutdown                                    | Previously queried state every two seconds. The current review replaces this with a subscription registered before shutdown.                                                                          |
| Windows bootstrap                                      | Bounded network reachability and management-address checks. An interface event alone does not establish endpoint reachability; Windows-native validation remains necessary for address-event changes. |
| Karakeep startup and forwarding                        | Bounded socket and HTTP readiness retries. File creation alone does not establish Docker or application readiness. Only the persistent keepalive was changed.                                         |
| macOS default-browser setup                            | Bounded Launch Services registration probes. The existing helper has no registration-completion event interface.                                                                                      |
| Telegraf and desktop metrics                           | Periodic measurements are the requested work. Their collection intervals remain unchanged.                                                                                                            |
| Storage health and maintenance                         | Timers perform health checks, detect stale reports, or schedule backups and maintenance. Replacing every timer with a path watch would lose stale-state detection.                                    |
| Steam package launcher                                 | Waits for the client, with backoff before a restart. It does not repeatedly inspect a running child.                                                                                                  |
| Clipboard, manifests, archives, and Git-object readers | Blocking event reads or finite input processing. A loop alone does not imply idle CPU consumption.                                                                                                    |

## Evidence and limits

Bluetooth's original readiness regression failed on repeated D-Bus requests.
Ten replacement cases passed against a private bus, including delayed adapters,
notifications during the initial snapshot, duplicate signals, multiple adapters,
timeouts, and rejected writes. The generated Nix command passed the same cases.

Karakeep's old wrapper failed prompt cancellation checks. All three signal cases
passed after repair. Thirteen MiniDV cases passed using real child processes and
selectable fixture descriptors. They cover idle waiting, disconnects, node
renumbering, escalation, monitoring failure, and retained data. The old finalizer
failed the single-probe requirement for both valid and invalid video fixtures.

The nix-seal workspace passed its Rust tests, strict Clippy checks, formatting,
and cargo-vet policy check. Nine focused subprocess cases cover completion,
timeouts, concurrent cancellation, reaping, and lost ownership. A syscall trace
showed one blocking wait during a 100 ms timeout; lost-ownership traces contained
no kill calls. Independent review found and prompted repair of that error path.

The integrated Nix build passed all 307 Python cases without skips. The nix-seal
release package and runtime activation and mount VM checks also passed.
Formatting and repository hooks passed after correcting a Darwin formatting
issue and executable permissions on two existing shell test scripts.

These results establish behavior on Linux fixtures, not whole-machine power
savings. Native Darwin behavior and physical FireWire events were not exercised.
Bluetooth tests did not change a real adapter. Nothing was activated or deployed.

## Owned command and fixture follow-up

The reusable `notification-process` Python package owns pipe exchange and one
blocking `waitid(WNOWAIT)` observer, keeps one monotonic deadline, terminates a
failed command's group while the leader retains its identity, and records the
final status using an untimed reap. Python-handled signals are deferred across
observer construction, startup, cleanup and final ownership transfer. Imported
libraries are declared through Python writers or interpreter environments.
[Python subprocess](https://docs.python.org/3/library/subprocess.html),
[Python process status](https://docs.python.org/3/library/os.html#os.waitid),
[Python signal masks](https://docs.python.org/3/library/signal.html#signal.pthread_sigmask).

Nonblocking input writes use the platform's `PIPE_BUF` guarantee and return to
descriptor readiness after `EAGAIN`. This matters on Darwin, where that guarantee
is smaller than Linux's. Output reads tolerate the same readiness race.
[POSIX pipe writes](https://pubs.opengroup.org/onlinepubs/9690949599/functions/write.html).

Simple fixture exit waits use Linux pidfds. Darwin subscribes to `SIGCHLD` with
kqueue before its initial non-reaping child snapshot, then rechecks only after
signals under the same deadline. A process `NOTE_EXIT` event alone was rejected:
XNU publishes it before the child becomes waitable, so registration can report
`ESRCH` while a nonblocking status snapshot still reports no exit.
[Linux pidfds](https://man7.org/linux/man-pages/man2/pidfd_open.2.html),
[Apple kqueue](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/kqueue.2.html),
[XNU exit ordering](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_exit.c).

Storage health takes one finite process-group snapshot while retaining the
leader's PID, parses kernel process-name bytes without assuming UTF-8, and kills
the owned group before reaping even when the snapshot finds no descendants.
The snapshot supplies diagnostic evidence rather than atomic absence proof.
A child in kernel-uninterruptible sleep can delay observer cleanup beyond the
communication deadline; a service manager remains the outer supervisor.

The manual Noctalia check consumes Hyprland's documented
[openlayer and closelayer events](https://wiki.hypr.land/ipc/), retaining brief
popups even when both notifications arrive before another state snapshot.
Firefox probes watch their owned log for Marionette's listening announcement;
[Gecko emits it after asyncListen](https://github.com/mozilla-firefox/firefox/blob/main/remote/marionette/server.sys.mjs).
The driver then makes the real protocol connection. Ghostty screen captures
subscribe before F12 and read only after a completed-write event.

HTTP services without a readiness notification retain bounded protocol retries.
AudioMuse and Maintainerr scripts report readiness attempts; their existing
systemd start deadlines bound the whole startup operation, including retries.
Desktop builders run one at a time with two compiler cores: simultaneous large
builders exceeded the daemon's reclaim threshold and stalled interactive work.

Manual Code probes subscribe to filesystem changes before reading Chromium's
`DevToolsActivePort`, then subscribe to browser target events before taking the
initial target snapshot. DOM readiness uses a native JavaScript
`MutationObserver`. Page reloads reinstall it only after execution-context
notifications, with a unique context identifier and one overall deadline.
[Node filesystem watch](https://nodejs.org/api/fs.html#fswatchfilename-options-listener),
[CDP Runtime lifecycle](https://github.com/ChromeDevTools/devtools-protocol/blob/master/json/js_protocol.json).

Disposable Code processes remain owned through startup failure and termination.
Linux uses a private systemd scope, runtime directory and session bus; macOS
launches the application bundle's native executable in an owned process group.
Native `posix_spawn` resets the child's signal mask while parent-side cancellation
is deferred until its PID is recorded. Cleanup kills the group before reaping its
leader. Linux regression cases cover an exited launcher, surviving descendants,
SIGTERM and a failed spawn. A native macOS GUI run confirmed target discovery and
DOM readiness before and after a real page reload, then cleaned up the fixture.
[Python native spawn](https://docs.python.org/3/library/os.html#os.posix_spawn).

The nested Hyprland fixture watches its native two-line `hyprland.lock`, which
is published after socket setup. This also avoids the pinned CLI's malformed
empty-instance JSON output. Headless output creation and monitor readiness share
the startup deadline. The owning shell subscribes to process exit before
requesting orderly shutdown.
[Pinned lock publication](https://github.com/hyprwm/Hyprland/blob/e368c13c27a42a173b9e08fa0bf413f9f7073187/src/Compositor.cpp),
[pinned instance parser](https://github.com/hyprwm/Hyprland/blob/e368c13c27a42a173b9e08fa0bf413f9f7073187/hyprctl/src/main.cpp).

Darwin's sandboxed Node check grants lookup of `com.apple.FSEvents`, matching
Nixpkgs' native Node sandbox profile. Without this permission directory watchers
report `EMFILE`; that error does not justify falling back to stat polling.
The grant belongs to the check derivation. Darwin validation uses the per-command
`--option sandbox relaxed`, which allows Nix to apply the declared profile without
changing machine-wide sandbox policy.
[Nixpkgs Node sandbox profile](https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/web/nodejs/nodejs.nix),
[Node watcher platforms](https://nodejs.org/api/fs.html#availability).

Scheduled work that uses the build queue must not be restarted and awaited by an
activation that owns that queue. A timer-only Home Manager backup uses
`[Unit] X-SwitchMethod=keep-old`; pinned sd-switch leaves changed active and
activating jobs alone. The timer still updates normally. This does not override
systemd dependencies or suppress a newly wanted service, so scheduled jobs must
remain outside the activation target's direct dependencies.
[Home Manager switch methods](https://nix-community.github.io/home-manager/options/home-manager/systemd.html#systemd.user.services.name.unit.x-switchmethod),
[pinned sd-switch planning](https://git.sr.ht/~rycee/sd-switch/blob/0.6.4/src/lib.rs).

Service ordering does not prove HTTP readiness. The music rescan delegates its
idempotent command-list read to curl's bounded protocol backoff, including
connection refusal. The API key is supplied through standard input. Nix declares
the retry count, retry budget and per-request deadline; the notification-based
process supervisor and systemd add overall deadlines. The command write is not
retried, because replaying a write can queue duplicate scans. HTTP fixture cases
cover temporary unavailability, an existing scan, rejected authentication and a
failed write.
[curl retry options](https://curl.se/docs/manpage.html#--retry),
[curl retry time bounds](https://curl.se/docs/manpage.html#--retry-max-time).
