# Extracting reusable local runtime features

Reviewed: 2026-10-14. Scope: local host/home behavior and its reusable module interfaces. Question: which upstream contracts should govern extracting supervised SSH forwards, runtime Jujutsu identity, VS Code Rust support, activation checks, runtime IWD profiles, adaptive I/O cost policy, and graphical Polkit authentication into reusable configuration?

## Answer

Use native module options where they already own the behavior. Add narrow opt-in interfaces for missing runtime behavior. Keep account identity, remote destinations, ports, credential files, device selection, and authorization policy with the consuming target. Assertions should reject incompatible configuration; runtime checks should validate facts unavailable during evaluation.

Source research inspected Home Manager `4b9add8645d5e2b0f7de18f7a442d08fe2bdcc91` and nixpkgs `c5c4a43b0e8056328ec4529f735cabdb8f1942bb`. Validation used the checkout's updated nixpkgs `c59305bab2065cfecc4944690d9eedbb56f3a9fa` with the same Home Manager revision. The inspected nixpkgs recipes select IWD 3.12 and systemd 260.2. Online documentation was retrieved on the review date. Recommendations below are design inferences unless explicitly described as upstream behavior.

## Findings and sources

### Supervised SSH forwards

OpenSSH distinguishes listener establishment from backend readiness. `ExitOnForwardFailure=yes` terminates failed forwarding setup, but a later connection failure to the forwarded destination does not terminate SSH. `BatchMode=yes` prevents interactive prompts. Strict host-key checking and authenticated keepalives are independent connection settings. Recommend enforcing these unattended defaults on the service invocation and letting the supervisor restart an exited process. Do not describe a running SSH process as proof that the backend application is healthy. [OpenSSH client configuration](https://man.openbsd.org/ssh_config.5)

Use foreground `ssh -N -T` without `-f`, with an argument vector rather than a generated shell command. IPv6 addresses in forwarding specifications require brackets. A local forward connects to its destination from the server; a reverse forward connects from the client. Default listener addresses to explicit loopback. A reverse listener's final exposure also depends on the server's `GatewayPorts` policy, which the client module cannot guarantee. [OpenSSH forwarding syntax](https://man.openbsd.org/ssh.1), [OpenSSH server forwarding policy](https://man.openbsd.org/sshd_config.5)

The implemented interface names one supervised forward per entry, with destination, direction, listener, target, package, optional SSH configuration and restart settings. An empty set starts nothing. Typed ports and an explicit acknowledgment protect non-loopback listeners. Preserve IPv6 loopback. Keep SSH host-key data and authentication provisioning independent of the tunnel module. Avoid global SSH changes. Isolate the service from connection multiplexing, and account for any forwards inherited from the selected SSH configuration. [Pinned Home Manager SSH module](https://github.com/nix-community/home-manager/blob/4b9add8645d5e2b0f7de18f7a442d08fe2bdcc91/modules/programs/ssh.nix)

On Linux, a user service can start with `default.target`, use a positive restart delay, and supervise the foreground process. On Darwin, Home Manager supports both `gui` and `user` domains; choose based on whether a graphical login is required. It reloads changed agents at activation. [Pinned Home Manager systemd module](https://github.com/nix-community/home-manager/blob/4b9add8645d5e2b0f7de18f7a442d08fe2bdcc91/modules/systemd.nix), [pinned launchd module](https://github.com/nix-community/home-manager/blob/4b9add8645d5e2b0f7de18f7a442d08fe2bdcc91/modules/launchd/default.nix)

launchd expects the directly launched process to remain in the foreground. `KeepAlive.SuccessfulExit=false` restarts unsuccessful exits; unconditional `KeepAlive=true` additionally restarts clean exits. Choose deliberately rather than claiming they are equivalent. `ThrottleInterval` bounds restart frequency. Check agent authentication environment and reconnect-after-sleep behavior on Darwin. [Apple launchd manual source](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchd.plist.5), [Apple launchd job guidance](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)

### Runtime Jujutsu identity

Jujutsu loads its user `config.toml` before `conf.d/*.toml`; fragments are processed lexicographically. `JJ_CONFIG` replaces these default user/system locations, and repository/workspace configuration remains applicable. A runtime identity fragment therefore overrides the generated user config, but does not guarantee final identity against repository settings or environment overrides. [Jujutsu configuration documentation](https://docs.jj-vcs.dev/latest/config/)

Home Manager writes `programs.jujutsu.settings` through a store-backed TOML generator. Its pinned module uses XDG configuration for Jujutsu 0.29 and newer on Darwin. Keep mutable identity outside that generated settings value. Expose a runtime TOML file source, or an explicit fallback that reads Git's global identity during activation. Use a string path option rather than copying a Nix path into the store. Activate after the write boundary and any declared credential producer. [Pinned Home Manager Jujutsu module](https://github.com/nix-community/home-manager/blob/4b9add8645d5e2b0f7de18f7a442d08fe2bdcc91/modules/programs/jujutsu.nix)

Recommend an atomic mode-0600 fragment in a mode-0700 directory, or a controlled link to a private runtime template. Do not put decrypted values in process arguments or diagnostics. Handle empty fallback identity and removal explicitly. Make signing behavior a separate option; selecting runtime identity should not impose a particular SSH key, signer catalog, or sign-on-push policy. Test quoted and Unicode names, replacement of stale links, missing inputs, repeated activation, and native Darwin paths.

### VS Code Rust support

rust-analyzer's official VS Code guide supports an explicit `rust-analyzer.server.path`. The extension and server are separate artifacts, and the extension has remote-editor installation behavior. A local Nix store server path is appropriate for a locally managed editor, but should not become an unquestioned default for a remote extension host. [Official VS Code integration guide](https://rust-analyzer.github.io/book/vs_code.html)

The documented defaults are `cargo.allTargets=true`, `check.allTargets=null` inheriting the Cargo choice, and `check.command="check"`. Selecting Clippy and denying warnings are valid opt-in policy, not prerequisites for functioning Rust support. Expose the selected package, all-target policy and warning policy; retain ordinary overridable editor settings for the check command, extra arguments and formatting policy. Do not attach private remote-server installation paths to this feature. [rust-analyzer configuration reference](https://rust-analyzer.github.io/book/configuration)

Home Manager's pinned VS Code module owns profiles and has distinct modules for editor forks. Compose Rust extension/settings into the intended profile without silently selecting unrelated language features or requiring a personal remote setup. Validate extension/settings evaluation independently from building Rust workspaces. [Pinned VS Code module](https://github.com/nix-community/home-manager/blob/4b9add8645d5e2b0f7de18f7a442d08fe2bdcc91/modules/programs/vscode/default.nix)

### NixOS activation checks

`system.preSwitchChecks` is an attribute set of shell fragments. Each receives the new closure as `$1` and the action as `$2`. The pinned generator runs fragments in separate subshells with effective `errexit`, reports failure, and exits early. Use this existing hook rather than adding a parallel activation framework. [Pinned pre-switch module](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/nixos/modules/system/activation/pre-switch-check.nix)

The switch implementation runs checks before installing the bootloader or switching services. `NIXOS_NO_CHECK=1` bypasses them. This is operational protection, not a security boundary. A hostname guard must define its behavior for initial installation, `boot`, `test`, dry activation, and deliberate renaming. Derive the expected identity from configuration and expose deliberate migration policy. Avoid interactive prompts in remote deployment. Diff display and hostname validation should be independently selectable. [Pinned switch implementation](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/by-name/sw/switch-to-configuration-ng/src/main.rs)

### Runtime IWD profiles

IWD stores and modifies network profiles in its state directory and monitors changes. A PSK profile filename is the SSID plus `.psk` only when its bytes are ASCII alphanumeric, space, underscore, or minus. Otherwise use `=` followed by lower-case hexadecimal SSID bytes, then `.psk`. Raw periods and other punctuation require encoding. The parser limits SSIDs to 32 bytes and validates encoded UTF-8. Implement this exact naming contract rather than merely rejecting path separators. [IWD 3.12 network documentation](https://kernel.googlesource.com/pub/scm/network/wireless/iwd/+/refs/tags/3.12/src/iwd.network.rst), [IWD 3.12 filename implementation](https://kernel.googlesource.com/pub/scm/network/wireless/iwd/+/refs/tags/3.12/src/storage.c)

Recommend named runtime sources containing a private SSID header and profile body. Validate the header and SSID length/encoding, and use the same ELL structural parser as IWD before replacing state. Python ConfigParser rejects native embedded PEM payloads and differs on delimiters, duplicate keys and section handling. The small validator passes private profile bytes over stdin, preserves those bytes after validation and emits no credential diagnostics. IWD still owns field semantics and authentication validity. [ELL 0.83 settings parser](https://kernel.googlesource.com/pub/scm/libs/ell/ell/+/refs/tags/0.83/ell/settings.c), [ELL native extension fixtures](https://kernel.googlesource.com/pub/scm/libs/ell/ell/+/refs/tags/0.83/unit/test-settings.c) Preserve root ownership, private directory/file modes, atomic writes, and a previously working profile when optional credentials are unavailable. Distinguish missing source recovery from malformed supplied input. Replace unexpected target symlinks atomically without modifying their referents; trusted runtime credential links require an explicit reading policy. Keep IWD's mutable file separate from immutable Nix store paths. Assertions should require IWD and reject incompatible IP-management expectations; do not impose systemd-networkd on every consumer. The native IWD module already owns its daemon, generated settings, and wireless-daemon compatibility assertion. [Pinned NixOS IWD module](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/nixos/modules/services/networking/iwd.nix)

### Adaptive I/O cost policy

The cgroup v2 I/O cost controller implements relative `io.weight` allocation. Its root-level `io.cost.model` and `io.cost.qos` accept `ctrl=auto`; specifying model or latency parameters switches to user control. The controller requires kernel support, and static coefficients need device measurements. An opt-in adaptive fallback can avoid inventing bandwidth/latency constants. Do not promise that configuring a unit's I/O weight alone activates the device controller. [Kernel cgroup v2 I/O documentation](https://cdn.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)

systemd 260.2's `90-iocost.rules` imports device-model/firmware hwdb properties and invokes its measured profile only when `IOCOST_SOLUTIONS` is populated. Preserve that authority. Generic fallback policy should select devices through options, handle existing and newly added disks, and skip calibrated hwdb devices. Also avoid overwriting explicitly user-controlled coefficients. Validate controller availability at runtime. Keep user-slice priority as a separate overridable policy. [Pinned systemd I/O cost rules](https://github.com/systemd/systemd/blob/v260.2/rules.d/90-iocost.rules), [systemd resource-control documentation source](https://github.com/systemd/systemd/blob/v260.2/man/systemd.resource-control.xml)

### Graphical Polkit agent

Polkit separates system authorization policy from the graphical authentication agent registered for a user session. Starting an agent does not imply changing administrator identities or granting authorization. Avoid bundling owner-specific authorization rules with agent selection. [Polkit architecture](https://polkit.pages.freedesktop.org/polkit/polkit.8.html), [agent registration documentation](https://polkit.pages.freedesktop.org/polkit/polkit-agents.html)

Prefer Home Manager's native `services.polkit-gnome`. Its unit is `polkit-gnome.service`, ordered after and wanted by `graphical-session.target`, with `PartOf` tying stop/restart behavior to that target. A previous differently named custom unit needs an explicit migration; do not accidentally run both agents. A compositor integration must actually manage the graphical target and session environment. Assert incompatible duplicate-agent selections where known, without coupling the agent to a particular compositor. [Pinned Home Manager agent module](https://github.com/nix-community/home-manager/blob/4b9add8645d5e2b0f7de18f7a442d08fe2bdcc91/modules/services/polkit-gnome.nix), [systemd desktop integration guidance](https://github.com/systemd/systemd/blob/main/docs/DESKTOP_ENVIRONMENTS.md)

## Implemented choices

The extraction reviewed local home application, editor and developer configuration,
shared identity policy, and local system activation, networking, hardware and
security configuration. Six features had coherent interfaces independent of the
account, hostname and secret provider:

| Feature | Reusable owner | Values retained locally |
| --- | --- | --- |
| SSH forwards | `modules/home/services/ssh-forwards.nix` | Destinations, ports, authentication and VM integration |
| Jujutsu identity | `modules/home/dev/jj-identity.nix` | Identity sources, credential declarations and signing policy |
| Rust editor support | `modules/home/vscode/languages/rust.nix` | Remote editor paths and stricter warning preference |
| Activation safety | `modules/nixos/system/activation-safety.nix` | Hostname selected by the host |
| IWD profiles | `modules/nixos/network/iwd-profiles.nix` | Secret templates and IP-management policy |
| I/O cost | `modules/nixos/hardware/iocost.nix` | Device selection, existing unit name and slice weights |

Home Manager already owns the Polkit agent. Reusing that module removes a custom
service while retaining authorization rules locally. Its `polkit-gnome.service`
conflicts with the previous custom unit to avoid two agents during migration.

The local workspace-service runner and cloud-drive integration remain local.
Their current contracts combine application-specific deployment, credential
production and operator workflow. Extracting them would require a separate
interface design; moving those bundles wholesale would export personal coupling.
Existing generic process, backup and recovery primitives can still serve them.

The new `lib/systemd/exec-args.nix` is a pure serializer used by SSH and IWD.
It escapes systemd percent specifiers and dollar expansion as well as argument
quoting. One-off lifecycle helpers remain beside their owning module. Retired
local script copies were removed after their callers migrated.

Both homes and the desktop system select the applicable modules. This is
configuration dogfooding; live activation remains a separate operation. The
[usage guide](../guide/runtime-features.md) records setup and lifecycle details.

## Validation and limits

Validation used a tracked-source snapshot including the new sources and the
existing uncommitted configuration, without changing lock files. Results:

- The Linux sandboxed Python suite passed 743 tests, with 57 generated-artifact
  or daemon integration cases deselected for their separate checks.
- Native macOS focused runtime and build-receipt tests passed 37 cases. Four
  native IWD integration cases were deselected there and passed separately in
  the Linux `iwd-runtime-profiles` check.
- The native IWD check exercised embedded certificates, repeated groups, native
  section continuation and rejected malformed input without replacing a working
  profile. Portable file tests covered SSID encoding, private modes, repeated
  provisioning and symlink handling.
- `local-feature-reuse` built on aarch64 Linux and Darwin. Its fixtures cover
  disabled modules, forwarding exposure and duplicate listeners, IPv6, strict
  SSH verification, independent runtime identity, Rust composition and ordinary
  setting overrides. Linux fixtures also cover IWD compatibility, ordering
  cycles, store credential rejection and explicit safe I/O device selection.
- `module-independence` built on aarch64 Linux, including Polkit manager and
  alternate-agent compatibility. Foreground SSH startup and generated Python
  helper checks built on Linux and Darwin.
- The native macOS `python-quality` check passed Ruff lint and formatting, ty
  analysis and bytecode compilation. Focused Nix formatting, Deadnix, ShellCheck,
  whitespace and documentation publication checks passed.
- The guide and generated option reference built successfully. The desktop
  NixOS closure and macOS system closure evaluated to derivations.

The receipt tests reproduced a separate `SystemExit(None)` and textual-exit
failure in the Linux package build helper. The fix retains Python's exit
semantics and the original exception while writing a numeric final receipt.
Two regression cases failed before the fix and passed afterward.

The installed Determinate Nix 3.23.0 evaluator crashed internally during contract
evaluation. Validation then succeeded with upstream Nix 2.34.8, already available
in the test environment. The system's installed Nix configuration was unchanged.

No configuration was activated. Real SSH reconnection, credential-producer
restart behavior, access-point authentication, I/O fairness and interactive
Polkit prompting still need native operational checks. The existing x86 I/O cost
VM check imports the reusable module but was not rerun in this pass. Structural
parser validation does not establish authentication validity or certificate trust.
