# Resource waits and repeated work

Reviewed: 2026-09-12. Scope: root-owned scripts, service timers, generated shell
templates, Windows bootstrap code, and runtime helpers in the three submodules.

## Changes

| Component | Previous work | Replacement |
| --- | --- | --- |
| [Bluetooth startup policy](../modules/nixos/hardware/scripts/disable-bluetooth-pairing.py) | Up to 100 separate property probes per adapter, spaced 100 ms apart | One connection subscribes to adapter-added signals before taking an ObjectManager snapshot. It sets pairing policy once per adapter and bounds the entire operation. |
| [Workload queue](../homes/desktop/local/wait-workstation-cgroup.py) | A systemd query and sleep every 200 ms after the main command exits | Blocking cgroup populated notifications retain the queue until descendants finish. |
| [MiniDV capture](../hosts/nixos/desktop/minidv/minidv-supervise.py) | A sysfs scan and several subprocesses each second; repeated child-exit probes during cancellation | A udev subscription, child pidfd, and signal descriptor share one blocking selector. Deadlines apply only during shutdown escalation. |
| [MiniDV finalization](../hosts/nixos/desktop/minidv/minidv-finalize.sh) | Two identical ffprobe invocations | One stream snapshot supplies both codec and audio checks. |
| [Karakeep launchd wrapper](../modules/home/scripts/karakeep-launchd.sh) | Hourly foreground sleeps, which could defer signal traps | An indefinite background sleep and interruptible shell wait; cancellation stops the keeper and runs Compose cleanup once. |
| [nix-seal subprocesses](../nix-seal/crates/nix-seal-runtime/src/child.rs) | Four child-status loops waking every 10 to 25 ms | One blocking observer per active child, with condition-variable deadlines and serialized cancellation/reaping. No dependency was added. |
| [Git privacy inspection](../modules/home/dev/scripts/git-privacy-hook.py) | Full-buffer lowercasing for every blocked pattern | Normalize once per chunk, retaining case-insensitive matching. |

BlueZ's ObjectManager supports discovery through a snapshot and subsequent
signals. Subscribing before the snapshot closes the registration race.
[BlueZ API guide](https://www.bluez.org/bluez-5-api-introduction-and-porting-guide/),
[D-Bus ObjectManager contract](https://dbus.freedesktop.org/doc/dbus-specification.html#standard-interfaces-objectmanager).

Linux cgroup notifications describe whether any descendants remain. MiniDV uses
udev's selectable monitor and a pidfd for its own child. The Rust observer uses
`waitid` with `WNOWAIT` so normal observation does not release the PID before
cancellation has finished. Reported loss of child ownership fails without
signalling that numeric PID.
[Cgroup notifications](https://docs.kernel.org/admin-guide/cgroup-v2.html#un-populated-notification),
[pyudev monitor API](https://pyudev.readthedocs.io/en/latest/api/pyudev.html#pyudev.Monitor),
[rustix waitid](https://docs.rs/rustix/latest/rustix/process/fn.waitid.html).

## Remaining waits

A bounded retry still deserves review. These retained waits have different
conditions or validation requirements from the notification replacements above.

| Location | Retained behavior and reason |
| --- | --- |
| Windows VM baseline checks | Read guest provisioning status every five seconds under an overall deadline. The current guest protocol provides a file read, not a completion notification. |
| Windows VM shutdown | Query state every two seconds, for at most five minutes. A lifecycle subscription remains an improvement candidate, but it needs confirmed registration before shutdown to avoid missing completion. This pass did not change the libvirt connection design. |
| Windows bootstrap | Bounded network reachability and management-address checks. An interface event alone does not establish endpoint reachability; Windows-native validation remains necessary for address-event changes. |
| Karakeep startup and forwarding | Bounded socket and HTTP readiness retries. File creation alone does not establish Docker or application readiness. Only the persistent keepalive was changed. |
| macOS default-browser setup | Bounded Launch Services registration probes. The existing helper has no registration-completion event interface. |
| Telegraf and desktop metrics | Periodic measurements are the requested work. Their collection intervals remain unchanged. |
| Storage health and maintenance | Timers perform health checks, detect stale reports, or schedule backups and maintenance. Replacing every timer with a path watch would lose stale-state detection. |
| Steam package launcher | Waits for the client, with backoff before a restart. It does not repeatedly inspect a running child. |
| Clipboard, manifests, archives, and Git-object readers | Blocking event reads or finite input processing. A loop alone does not imply idle CPU consumption. |

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
