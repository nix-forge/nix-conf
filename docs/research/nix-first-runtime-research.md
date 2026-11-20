# Nix-first configuration and Rust runtime helpers

Reviewed 2026-11-17 against the root working tree. Independent agents researched
native configuration and Rust architecture, implemented separate feature domains,
and reviewed the integrated boundaries. This note records the decision, completed
migration and validation limits. Submodules and upstream application sources
retain their independent ownership and release history.

## Decision

Use native NixOS, Home Manager and nix-darwin options first. Generate immutable
JSON, TOML, XML and other configuration with Nix generators. Prefer package
combinators and service-manager directives over custom scripts. Nix evaluation
cannot safely inspect mutable runtime state or materialize private credentials
in the store. Use feature-local Rust programs for those operations.

Preserve writable application preferences and unrelated UI changes. Retain mount
conditions around volume-specific preparation: global tmpfiles can otherwise
write into an unmounted filesystem. Ordered native commands are sufficient for
simple oneshot directory preparation. Sources:
[Nixpkgs format generators and builders](https://nixos.org/manual/nixpkgs/stable/),
[systemd service commands](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html#ExecStart=).

## Completed transitions

The original root inventory contained 67 Python sources. All project-owned
Python implementations are migrated or retired. C validators, AWK parsers,
Expect credential exchange and substantive shell state machines were also
reviewed. This inventory excludes independently owned submodules and upstream
application dependencies; it is not a claim to remove supported configuration
languages or every shell command.

| Owner | Implemented replacement and retained contract |
| --- | --- |
| Shared Fontconfig | Native `linkFarm` output composition; Rust family discovery/XML generation with deterministic order and correct escaping |
| Immutable directories and service policy | Native install commands, systemd conditions/dependencies and Nix-generated policy files |
| Helium | Streaming Rust CRX extraction, staged background extension refresh and mutable preference reconciliation; next-launch loading, previous-version retention and canonical policy hashes retained |
| Gecko and default browser | Rust installation registry and Launch Services registration checks; CRLF, unrelated profiles and application identity preserved |
| Spotify, XDG, LibreOffice, palette | Rust preference/XML/JSON reconciliation; unmanaged state, idempotence and atomic publication retained |
| Desktop session policy | Rust inhibitor, clipboard and lock observers/controllers; per-session ownership, subscribe-before-snapshot and bounded IPC |
| Wallpaper | Rust private atomic local imports, effective policy, Commons/ESA acquisition and rotation; image admission, licenses, provenance, geometry, retention and black fallback retained |
| Private workspace and Git identity | Rust ownership/mode/link guards, private dispatch, staged-content privacy and Jujutsu identity protection |
| Adaptive I/O cost | Nix-generated device selection and udev/systemd policy with Rust reconciliation; measured operator policy wins, disappearing disks are skipped and each controller command uses one write |
| IWD, BlueZ and native validators | Rust materialization/D-Bus plus narrow GTK4/ELL FFI adapters; authoritative upstream parsing and runtime credential boundaries retained |
| libvirt and Windows | Nix-generated policy/XML inputs with Rust control, seed assembly and lifecycle shutdown; UUID, disk, media, profile, VFIO and discard gates retained |
| Application recovery and antivirus | Rust process ownership/deadlines and regular-file descriptor scanning |
| Storage | Rust capacity, health, retention, backup/database export, retirement, installer preparation, enrollment and protected boot-generation checks |
| Homelab and music | Rust service-local HTTP protocols, Actual CLI/vault lifecycle, account/plugin bootstrap, private PTY exchange and credential synchronization; mount vetoes, token refresh policy, cancellation ownership and secret-safe diagnostics retained |
| Cloud and desktop resource controls | Rust rclone state, Codex launch/task/pressure tools and SQLite history bounds |
| Developer and build operations | Rust worktree lifecycle, remote realization, Linux package builds, hosted CI candidate selection, verified source exports and evidence receipts; hosted exclusions, lazy Nix projection and historical fallback retained |
| macOS application management | Rust registry, readiness, lifecycle, Dock state/reconciliation and signing orchestration; Nix generates ordered Dock actions, with full preflight and private atomic receipts |
| Compiler coverage | Native Nix validates explicit TypeScript projects and strict options; direct compiler commands replace the Node discovery program |
| Documentation site | Native Nix file composition and feature-table generation, with `nixosOptionsDoc` Markdown and upstream MkDocs/Pygments; the unnecessary Rust renderer was removed |

Unused Samsung power-state code and the unselected legacy Zen dictation module
were retired. Active desktop dictation remains selected. Font-family escaping
also corrects a legacy defect: reserved characters now produce valid XML entities
instead of being escaped twice. The CRX tool extracts a payload; it does not
authenticate signatures.

## Declarative refinement

A follow-up audit replaced the guide's Rust staging and reference renderer with
`linkFarm`, `writeText`, `concatText` and native `nixosOptionsDoc` Markdown.
Feature data and module declarations already belong to Nix; rebuilding their
parsers and renderers in Rust added an unnecessary compiler dependency and
serialization boundary. The JSON option package remains available. Built option
Markdown is concatenated by derivations, never read during evaluation, so the
site builds with import-from-derivation disabled.

Font discovery remains a build-time Rust operation: its font files are derivation
outputs, unavailable to pure evaluation. Palette correction retains Rust's
fractional gamma calculation and contrast search. Runtime reconcilers retain
Rust where they inspect mutable state, perform I/O or handle private credentials.
Replacing those with evaluator reads would weaken reproducibility or leak secrets.

## Rust configuration

The root Cargo workspace explicitly lists feature-local crates. It shares edition
2024, resolver 3, Rust 1.99, package metadata, dependencies and lint policy.
Submodule workspaces remain independent. Reusable algorithms are limited to
actual multiple callers, including process-group cleanup and legacy number
formatting. Source: [Cargo workspaces](https://doc.rust-lang.org/stable/cargo/reference/workspaces.html).

[The runtime registry](../../flake/runtime-packages.nix) builds individual packages
with the pinned Nixpkgs `rustPlatform.buildRustPackage`, a committed lockfile and
a restricted source fileset. Cargo dependencies compile offline in the Nix
sandbox. Native GTK4, ELL, libvirt and SQLite inputs are declared explicitly. The pressure
monitor links the pinned Nix SQLite instead of a second bundled copy. Platform
metadata excludes Linux-only packages from Darwin compilation. The default shell
includes the native compiler and libraries required by build scripts. No floating
Rustup selection or additional toolchain flake input is required.
Source: [Nixpkgs Rust packaging](https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/rust.section.md).

Workspace code forbids unsafe Rust and denies unwrap, expect and panic. Four
native boundaries explicitly scope unsafe code: libvirt events, GTK parsing, ELL
settings and Darwin process/signing inspection. Each boundary records its ABI and
owns callback/context cleanup. Safe libraries handle ordinary files, sockets,
PTYs, HTTP, XML, JSON and process management. Native subprocesses use argument
lists; cancellation kills owned groups before their leader can be reaped and its
PID reused. Credential prompts use native terminal descriptors and restore the
exact prior attributes on cancellation; their entry point also owns cancellation
of native commands and held-open worker input. None of these implementation
choices establish measured performance improvements.

Rustfmt, Clippy and rustdoc run through `rust-quality`, with warnings denied.
The gate also checks dependency licenses, bans and sources offline; CI refreshes
advisories separately. The [quality and design follow-up](rust-quality-design-research.md)
records the lint policy, inventory derivation and validation limits. Package
checks compile each runtime output. Thin LTO and stripped debug symbols apply to
release builds. Sources:
[Cargo profiles](https://doc.rust-lang.org/stable/cargo/reference/profiles.html),
[Clippy usage](https://doc.rust-lang.org/clippy/usage.html).

Dependency auditing found vulnerable older XML, time and bundled SQLite versions
under the original compiler compatibility ceiling. Raising the workspace compiler
requirement to the already pinned toolchain allowed patched dependencies. The
recorder uses the existing workspace time library rather than adding an
unmaintained date dependency. Advisory checks use current network data and remain
separate from reproducible compilation. Examples of the upstream advisories:
[SQLite](https://rustsec.org/advisories/RUSTSEC-2026-0459),
[XML parser](https://rustsec.org/advisories/RUSTSEC-2026-0194),
[time parser](https://rustsec.org/advisories/RUSTSEC-2026-0009).

## Maintenance and retained languages

Use the pinned shell, then run:

```sh
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked --offline -- -D warnings
cargo audit
nix build --no-link .#checks.x86_64-linux.rust-quality
```

The offline Cargo invocation requires its cache to be populated; the Nix check
owns dependency fetching and sandboxed compilation. Darwin checks select only
supported packages. Root retained tests cover Nix library functions through
`nix-unit`; no root Rust or Python behavioral suite is introduced.

The static `runtime-source-policy` check rejects new root-owned Python, C, AWK
and Tcl/Expect implementations. Obsolete Python imports, Ruff/ty/compileall hooks,
formatting rules, configuration and CI cache profile were removed. CI now uses
the native Rust quality gate and matching `ciRust` tool environment.

Keep these deliberate interfaces in their required language:

- Swift AppKit, Network and application launch adapters, and JXA application
  inventory, where the OS interface owns callbacks, consent or application data.
- mpv Lua, compositor Lua configuration, Nushell/shell initialization and
  application-required JavaScript or exact upstream patch fragments.
- Structured configuration and schema filters, platform provisioning files, and
  minimal build/activation/PATH/exec glue invoking declared native tools.
- Upstream application dependencies, including Python-based documentation tools,
  and all independently owned submodule sources.

Do not introduce a Rust interpreter launcher around an old algorithm. Keep policy
in Nix and pass it as data. Extend the owning feature crate rather than creating
an unrelated global utility collection.

## Validation and limits

The runtime migration passed 57 x86_64 Linux checks before the declarative guide
refinement removed its Rust package check. All runtime
release package builds and Rust quality checks passed; the final combined run
also covers source policy, documentation, formatting and hooks.
`just test` passed all 12 Nix library cases. The current Cargo advisory scan
reported no findings. Desktop and configured Darwin system derivations evaluated
through dry-run builds; no full system closure was built, activated or deployed.

Temporary fixture exercises outside the repository cover legacy JSON/hash
compatibility, private files and atomic updates, process cancellation and
surviving descendants, private D-Bus signals and owner changes, file-descriptor
scanning, API failure paths, credential synchronization, worktree/source identity,
backup/retention guards, VM/media refusal paths, PTY prompts and native parser
behavior. Continuation fixtures also exercise CI policy and projection, extension
staging and deadlines, Dock drift/receipts, IOCost command boundaries and Actual
lock/request cancellation in a disposable mount namespace. Local ZIP fixtures use
the real extractor to verify traversal and symlink rejection. GTK and ELL outputs
were compared with the removed C programs using the same native libraries. libvirt callback behavior was exercised with an ABI
mock; real guests were not changed. These exercises are not retained suites or
proof of production recovery behavior.

Native Darwin execution/linking, real hardware enrollment, VFIO transitions,
Windows installation, production account changes, live wallpaper downloads and
backup restoration were not performed. Source exports and evidence recording
fail closed for non-UTF-8 indexed filenames; exports also reject non-UTF-8 link
targets rather than certifying a lossy snapshot. Existing UTF-8 source identities
retain their canonical serialization. External commands that deliberately escape
the owned session remain outside process-group cleanup guarantees. Nested VM
controllers acknowledge cancellation through exit after their own cleanup; an
externally stopped or unresponsive controller can delay that acknowledgement.
Leaf commands have bounded TERM grace. SIGKILL cannot guarantee temporary-file
or terminal cleanup.
