# A Rust controller for WireGuard roaming on macOS

Research date: 2026-09-02

## Scope

This note covers a Rust replacement for the repository's nix-darwin WireGuard
roaming shell controller. It does not replace WireGuard, `wireguard-go`, or
`wg-quick`. The controller decides when to start or stop the existing tunnel,
checks its health, and restores the ordinary network after a failure.

The repository pins nix-darwin at
[`4cff07de`](https://github.com/nix-darwin/nix-darwin/tree/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48)
and Nixpkgs at
[`9fbb54b3`](https://github.com/NixOS/nixpkgs/tree/9fbb54b33e91ee4ca368e35a78e0613c720600b3).
No machine-specific network names, tunnel addresses, endpoints, or keys appear
in this note.

## Recommendation

Replace the 466-line shell policy controller with a small synchronous Rust
program. Keep the upstream WireGuard tools for interface, route, endpoint, and
DNS setup. Rust improves the root control plane through typed states, exact
argument passing, bounded parsing, reliable file locks, and testable rollback.
It does not improve packet throughput because `wireguard-go` carries the data
path.

Do not add Tokio, an HTTP client stack, a CLI framework, or a WireGuard
protocol crate. This daemon wakes about once per minute. Its work consists of a
few short system queries and occasional `wg-quick` transitions. The standard
library plus `signal-hook` is enough. `signal-hook` provides a safe Unix signal
iterator and keeps signal-handler work out of application code.
([Rust process API](https://doc.rust-lang.org/std/process/struct.Command.html),
[`signal-hook` iterator](https://docs.rs/signal-hook/latest/signal_hook/iterator/))

The recommended program structure is:

```text
configuration -> observation -> pure policy decision -> transition executor
                       ^                                  |
                       +---------- next reconcile <-------+
```

`Observation` should contain enums for SSID availability, tunnel state,
native VPN state, ordinary-route availability, handshake age, and connectivity.
The policy function returns an action such as `KeepDown`, `BringUp`,
`KeepUp`, or `BringDown`. It must not perform I/O. A `System` trait owns command
execution and filesystem access. Unit tests can then cover the decision matrix
without changing the developer's routes or DNS.

## Keep `wg-quick` as the network transaction owner

nix-darwin's module generates `/etc/wireguard/<name>.conf`, loads private and
preshared keys from external files in a post-up script, and installs
Nixpkgs `wireguard-tools` plus `wireguard-go`. The roaming interface must remain
`autostart = false`; the Rust controller invokes it.
([pinned nix-darwin module](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/services/wg-quick.nix#L126-L230),
[pinned WireGuard tools package](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/pkgs/by-name/wi/wireguard-tools/package.nix#L16-L89))

The Darwin `wg-quick` implementation already handles the hard network work. It
creates a `utun`, installs two `/1` routes for an IPv4 default route, preserves
a direct route to the peer endpoint, changes DNS, watches route changes, and
restores routes and DNS on shutdown. Reimplementing that code in Rust would
duplicate upstream behavior and create more ways to strand the machine.
([interface and route cleanup](https://git.zx2c4.com/wireguard-tools/tree/src/wg-quick/darwin.bash?id=139aac59a5ab7da913d4b6dd62692fa90e2ccad4#n641),
[endpoint routing](https://git.zx2c4.com/wireguard-tools/tree/src/wg-quick/darwin.bash?id=139aac59a5ab7da913d4b6dd62692fa90e2ccad4#n723),
[DNS and route monitor](https://git.zx2c4.com/wireguard-tools/tree/src/wg-quick/darwin.bash?id=139aac59a5ab7da913d4b6dd62692fa90e2ccad4#n749),
[default-route setup](https://git.zx2c4.com/wireguard-tools/tree/src/wg-quick/darwin.bash?id=139aac59a5ab7da913d4b6dd62692fa90e2ccad4#n879))

There is one unavoidable shell boundary. Upstream `wg-quick` evaluates
`PreUp`, `PostUp`, `PreDown`, and `PostDown` as shell snippets. Only allow the
declaratively generated nix-darwin profile here. Never accept an arbitrary
profile path from the network or an unprivileged user.
([upstream hook execution](https://git.zx2c4.com/wireguard-tools/tree/src/wg-quick/darwin.bash?id=139aac59a5ab7da913d4b6dd62692fa90e2ccad4#n942))

## Process execution

Every child must use `std::process::Command` with a fixed absolute executable
path and one argument per field. Do not invoke `sh -c`, interpolate command
strings, or print `Command` with its arguments. Rust searches `PATH` for a
non-absolute program, so the Nix module should pass store paths for `wg`,
`wg-quick`, and `curl`; Apple tools should use their fixed `/usr/bin`,
`/usr/sbin`, `/bin`, or `/sbin` paths.
([`Command::new`](https://doc.rust-lang.org/std/process/struct.Command.html#method.new))

Clear the child environment and add only the values required by the command,
including `LC_ALL=C` and the known system and Nix tool paths needed by
`wg-quick`. Set stdin to null. Capture output only for commands whose output is
parsed, and never include captured output in ordinary errors. SSID and `wg`
output can contain values that must not reach the log.

The HTTPS probe should continue to use the Nix-built curl rather than adding a
second TLS implementation to the daemon. Put `--disable` first so curl ignores
per-user configuration. Restrict both the original URL and redirects to HTTPS,
force IPv4 for this IPv4 tunnel, discard the response body, and apply connect,
overall, and redirect limits. Curl documents that `--connect-timeout` covers
DNS, TCP, and TLS setup while `--max-time` covers the complete transfer.
([curl command reference](https://curl.se/docs/manpage.html),
[curl timeout guidance](https://curl.se/docs/faq.html))

## Launchd lifecycle and signals

Run the program in the foreground as a system LaunchDaemon. Apple explicitly
says a launchd process must not daemonize and should handle `SIGTERM`; launchd
sends `SIGTERM` during shutdown. The handler must only notify the main loop.
The main loop then acquires the transition lock and runs the normal tunnel-down
path before exiting.
([Apple launchd process rules](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html),
[Apple daemon lifecycle](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/Lifecycle.html))

Use a signal thread and `mpsc::Receiver::recv_timeout` in the main loop. This
makes `SIGTERM` responsive even while the controller waits for its next
reconcile deadline. `SIGHUP` can request an immediate reconcile. Do not perform
filesystem or process operations inside a signal handler.

Recommended plist values are `KeepAlive = true`, `RunAtLoad = true`,
`ProcessType = "Background"`, `ThrottleInterval = 10`, `ExitTimeOut = 30`,
`Umask = "0077"`, and `AbandonProcessGroup = false`. The last value lets
launchd clean up a forgotten child process if the controller crashes. The
program should normally finish its own shutdown well before the 30-second
limit. The local `launchd.plist(5)` manual documents these keys, and Apple says
jobs that exit too quickly may be treated as crashing.
([Apple launchd job configuration](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html#//apple_ref/doc/uid/10000172i-SW7),
[nix-darwin launchd installation](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/system/launchd.nix#L55-L165))

## Root and filesystem safety

Network route changes require root on macOS. Keep the actuator as a root
LaunchDaemon and make every mutating manual action verify effective UID zero.
The controller should never read the WireGuard private key. It validates the
key file's owner and mode, then lets the existing nix-darwin post-up script
give the path to `wg`. This keeps key material out of Rust memory and logs.

Use `/private/var/run`, not `/var`, to avoid macOS's `/var` symlink. Create one
root-owned runtime directory per validated interface name with mode `0700`.
For the trusted-network file and every controller file:

- open with `O_NOFOLLOW` through `OpenOptionsExt::custom_flags`;
- inspect metadata on the opened descriptor, not by a separate path lookup;
- require a regular file owned by root with no group or other permission bits;
- cap reads and reject NUL, extra lines, or malformed UTF-8;
- create new files with explicit `0600` mode and a process umask of `077`.

Rust's Unix `OpenOptionsExt` exposes the creation mode and `O_NOFOLLOW` custom
flag. Its `File::try_lock` maps to nonblocking `flock` on Unix and releases the
lock when the descriptor closes. Use two locks: an instance lock held for the
life of `run`, and a transition lock held only while observing and applying a
state change. This avoids PID-file reuse and stale-directory cleanup.
([Unix open options](https://doc.rust-lang.org/std/os/unix/fs/trait.OpenOptionsExt.html),
[`File::try_lock`](https://doc.rust-lang.org/std/fs/struct.File.html#method.try_lock))

Write policy state by creating a unique file in the private directory, calling
`sync_all`, renaming over the destination, and syncing the directory. State
values must be closed enum labels. Never write the observed or trusted SSID,
command output, a private key, or a peer endpoint.

## Reconciliation and fail-open rollback

Each iteration must observe current state again while holding the transition
lock. Never act on a queued observation. Use this priority order:

1. A pause request, disabled automatic mode, active native macOS VPN, missing
   secret, or trusted network requires the tunnel down.
2. Unknown SSID follows the configured policy. `disconnect` remains the safe
   default because an API denial or Wi-Fi transition cannot be mistaken for an
   away network.
3. An away network may start the tunnel only after the ordinary default route
   and HTTPS probe work.
4. After `wg-quick up`, require the expected `utun`, tunnel routes, a fresh
   handshake within the activation deadline, and a successful HTTPS probe.
5. Any failed activation or health check runs the same idempotent down path.

WireGuard's `wg show <interface> latest-handshakes` output gives epoch seconds
for each peer. Parse it in Rust, do not pipe it through `awk`, and never log the
line because it also contains the peer's public key. The activation test should
require a handshake no older than the start of that attempt. A steady-state
check should also reject an implausibly old handshake.
([`wg` show fields](https://git.zx2c4.com/wireguard-tools/tree/src/man/wg.8#n67),
[official WireGuard quick start](https://www.wireguard.com/quickstart/))

The down path should first ask `wg-quick down` to restore the routes and DNS it
owns. If that fails, remove only routes that point at the validated `utun`,
remove only the validated WireGuard socket and name file, and remove only IPv6
blackhole routes recorded in this controller's journal. Run an ordinary-route
and HTTPS check afterward. Failure to prove recovery must produce a distinct
state and nonzero manual-command exit code, while the daemon keeps retrying.

IPv6 blocking is a small transaction. Record intent in the private runtime
directory before adding `::/1` and `8000::/1`, record each successful add, and
remove recorded routes on every down, failure, or startup-recovery path. If
either add fails, roll back the first route and tear down the tunnel. macOS
`route(8)` documents `-blackhole` and restricts route mutation to the
super-user. Upstream `wg-quick` uses the same two `/1` pattern for default
routes.

`wg-quick` saves DNS settings in its route-monitor process. A crash at the
wrong time can lose that in-memory snapshot. Before bringing the tunnel up,
the Rust controller should save the exact DNS and search-domain settings for
each network service in a root-only file under
`/private/var/db/wireguard-roaming`. Restore that snapshot after a failed down
and delete it only after ordinary connectivity succeeds. This is safer than
resetting every service to automatic DNS. Keep the existing "reset to
automatic" behavior as an explicitly named emergency command, not the normal
rollback path. The Darwin `wg-quick` source confirms that it changes and
restores every network service through `networksetup`.
([upstream DNS transaction](https://git.zx2c4.com/wireguard-tools/tree/src/wg-quick/darwin.bash?id=139aac59a5ab7da913d4b6dd62692fa90e2ccad4#n749))

## The macOS SSID constraint

CoreWLAN is Apple's public API. `CWWiFiClient` provides Wi-Fi interfaces and
`CWInterface.ssid()` dynamically returns the current network name. On current
macOS, access to SSID data requires Location permission.
([CoreWLAN overview](https://developer.apple.com/documentation/corewlan),
[`CWInterface.ssid()`](https://developer.apple.com/documentation/corewlan/cwinterface/ssid%28%29))

Apple Developer Technical Support states that a LaunchDaemon cannot gain that
permission. Apple's supported design is a user LaunchAgent associated with an
app that receives Location permission, with the agent reporting Wi-Fi state to
the privileged daemon. This matters: moving the existing SSID query into Rust
and linking CoreWLAN directly would return `nil` in the root daemon on current
macOS.
([Apple DTS answer about SSID access from a LaunchDaemon](https://developer.apple.com/forums/thread/759044),
[Apple DTS note on the macOS Location requirement](https://developer.apple.com/forums/thread/732431?answerId=758114022#758114022))

The practical first implementation should retain
`/usr/sbin/ipconfig getsummary <interface>` through the safe command runner.
`ipconfig(8)` documents `getsummary`, and the current controller has already
worked on the target Mac. Treat missing or unparsable output as `Unknown`; do
not fall back to guessing from interface names or IP ranges. Add an optional
host-local Wi-Fi interface setting so a machine can avoid parsing localized
`networksetup` hardware-port output.

Long term, split SSID observation into a user LaunchAgent using CoreWLAN and a
root actuator. Use a root-owned Unix socket, authenticate the peer credentials,
and send a small length-delimited observation. Do not write the SSID to disk or
logs. This extra process is justified only when the command-line query stops
working or native event-driven roaming is worth the packaging and Location
permission UX.

## Testing and Nix packaging

Put the generic crate in `nixpkgs-personal` and build it with
`rustPlatform.buildRustPackage`. Keep the Darwin module limited to service
policy and package selection. Commit `Cargo.lock` and use
`cargoLock.lockFile`; Nixpkgs fetches each locked crates.io dependency as a
fixed-output derivation. `buildRustPackage` runs release-mode tests by default.
Use `lib.fileset.toSource` or an equally narrow source filter so unrelated
repository changes do not rebuild the controller.
([Nixpkgs Rust packaging manual](https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/rust.section.md#compiling-rust-applications-with-cargo))

The minimum useful test suite includes:

- a table test for every policy input, especially pause, native VPN, trusted,
  away, unknown, unhealthy tunnel, and unavailable secret;
- parser tests for empty, malformed, non-UTF-8, oversized, and adversarial
  command output;
- a fake `System` test that proves all activation failures call down and remove
  recorded IPv6 routes;
- order tests for preflight, up, handshake, postflight, down, exact DNS restore,
  and final ordinary-connectivity proof;
- lock tests with two processes, not only two threads;
- signal tests that prove `SIGTERM` requests down and exits within launchd's
  timeout;
- Darwin integration tests with fake executables that print fixtures and
  record argument arrays, proving no shell expansion occurs;
- Nix evaluation assertions for an external private-key file, external trusted
  SSID file, a non-autostart selected interface, and absolute log and runtime
  paths.

Run `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo
test`, a Nix package build, the full Darwin system build, and `nix flake check
--no-build`. Live rollout still needs manual up, forced activation failure,
down, DNS restoration, away-network, trusted-network, and sleep/wake checks.

## Acceptance standard

The Rust replacement is ready only when it preserves the current command
interface and fail-open behavior, adds exact DNS snapshot restoration, handles
`SIGTERM`, serializes every transition with descriptor locks, logs only enum
state labels, and passes the pure policy and fake-system rollback suite. A
smaller binary or faster loop is welcome, but those are not the reason to ship
the rewrite. The reason is that a root network policy controller becomes
auditable and its failure paths become executable tests.
