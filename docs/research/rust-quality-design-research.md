# Rust quality gates and Nix-first runtime design

Reviewed: 2026-11-17. Scope: the root Cargo workspace and its Nix packaging;
independently owned submodules and upstream package sources are excluded.

## Answer

Keep feature-local Rust helpers. Nix selects features, validates configuration,
generates immutable policy and packages native dependencies. Rust implements
runtime algorithms, mutable-state reconciliation, protocol handling and narrowly
scoped native adapters. Strengthen common lint policy, dependency checks and
packaging inventory so adding a feature cannot silently omit its source, checks
or safety rules. Avoid a global runtime framework or recreating Nix configuration
rendering in Rust merely to share code.

This recommendation follows source inspection and official tool contracts. It is
not a complete runtime audit or evidence of measured performance. The existing
[migration research](nix-first-runtime-research.md) records current behavior and
its native-platform limitations.

## Findings and sources

### Keep policy with Nix and mechanisms with their feature

Observed: the root workspace spans browser/application reconciliation, desktop
observers, storage/homelab operations, process ownership, native adapters and
build/development commands. The registry uses `rustPlatform.buildRustPackage`,
a committed lockfile and explicit native libraries.

Nixpkgs provides Rust packaging and format generators. Inference: keep service
selection, executable paths, activation ordering, credentials delivery and
immutable JSON/TOML/XML in Nix. Helpers accept those inputs and validate runtime
state before mutation. Source:
[Nixpkgs manual](https://nixos.org/manual/nixpkgs/unstable/).

| Root Rust responsibility | Recommended interface and ownership |
| --- | --- |
| Preferences and application reconciliation | Explicit input and destination, unmanaged-value preservation, idempotence and atomic publication |
| Desktop/cloud/pressure observers | Service-manager lifecycle, subscribe before snapshot, notification waits and cancellation |
| Storage, VM, credentials and homelab operations | Preflight validation, native argument lists, operation deadlines and secret-safe diagnostics |
| Source export, package selection and receipts | Deterministic structured data; preserve Nix licensing/build policy |
| Fonts, palette and archive processing | Pure or streaming algorithms over build outputs/runtime inputs; avoid mutable evaluator reads |
| GTK/ELL/libvirt/Darwin adapters | Small safe interface; document ABI, lifetimes and ownership beside unsafe operations |
| Shared libraries | Share behavior across actual callers; keep differing feature policy local |

### Derive packaging coverage from the existing inventories

Observed: Cargo member paths, runtime source fileset and package checks duplicate
much of the same inventory. A new crate could compile locally while missing its
Nix source or package check. Cargo workspaces share a lockfile and inherited
metadata; Nix can parse TOML. Inference: derive the restricted source fileset from
explicit Cargo member paths, retaining separately declared non-crate assets; derive
package checks from the runtime registry where stable names permit it. Platform
support and native dependencies remain Nix policy. Sources:
[Cargo workspaces](https://doc.rust-lang.org/cargo/reference/workspaces.html),
[Nix TOML parsing](https://nix.dev/manual/nix/2.34/language/builtins.html#builtins-fromTOML).

### Apply common lints to every member

Observed: four native-adapter manifests opt out of the workspace lint table to
allow scoped unsafe code. New workspace rules alone do not cover them. Preserve
ordinary-code unsafe prohibition while giving adapters the same remaining policy.
Native exceptions should be narrow, reasoned and accompanied by safety arguments.
Rust distinguishes overridable `deny` from non-overridable `forbid`; Cargo lints
apply per package. Sources:
[Rust lint levels](https://doc.rust-lang.org/rustc/lints/levels.html),
[Cargo manifest lints](https://doc.rust-lang.org/cargo/reference/manifest.html#the-lints-section).

Retain format, all-target Clippy, denied warnings and native release builds. Add
applicable rules for unfinished code, discarded must-use results, lock guards
across await, unused results and unsafe documentation. Compilation checks omit
final code generation, so they cannot replace package builds. Sources:
[Clippy usage](https://doc.rust-lang.org/clippy/usage.html),
[Cargo check](https://doc.rust-lang.org/cargo/commands/cargo-check.html).

Use rustdoc warnings to catch malformed documentation and broken links for shared
interfaces. Do not indiscriminately copy service-specific benchmark gates,
proof targets, coverage thresholds or behavioral suites: root retained testing
policy differs from an application repository.

### Separate reproducible dependency policy from current advisories

Cargo-deny checks licenses, sources, dependency bans and advisories; its CLI can
select individual checks. `--offline` disables all network access, including
advisory updates and standard-library replacement data. Thus
`cargo deny --locked --offline check licenses bans sources` belongs with vendored
sandbox checks, and `cargo deny --locked check advisories` belongs in a networked
maintenance/CI step. A cached check must not imply current vulnerability coverage.
Sources: [cargo-deny checks](https://embarkstudios.github.io/cargo-deny/checks/index.html),
[common CLI](https://embarkstudios.github.io/cargo-deny/cli/common.html),
[check selection](https://embarkstudios.github.io/cargo-deny/cli/check.html).

Cargo-machete heuristically detects unused direct dependencies and supports
explicit exceptions; review them rather than suppressing whole directories.
Source: [cargo-machete](https://github.com/bnjbvr/cargo-machete).

Semgrep supports Rust, and can express project-specific syntactic patterns.
Its community analysis has single-function/file limitations. Inference: use
compiler-backed Clippy for unwrap, panic, todo and debug rules; introduce Semgrep
rules when they cover a concrete repository invariant beyond those lints. Do not
claim the tools provide equivalent semantic coverage. Sources:
[Semgrep Rust support](https://semgrep.dev/products/product-updates/rust-ga-support-and-swift-beta-support/),
[Semgrep project](https://github.com/semgrep/semgrep).

### Enforce transport and queue rules through resolved methods

The implemented `clippy.toml` rejects TLS-verification bypass methods and
unbounded Tokio/standard-library channels. Clippy resolves configured paths,
so renamed imports still refer to the banned method. This deliberately rejects
any invocation of a TLS bypass setter, including one passing `false`; callers
should retain the verified default instead. These rules do not establish bounds
on every queue, socket, HTTP response or WebSocket allocation. Source:
[Clippy disallowed methods](https://doc.rust-lang.org/clippy/lint_configuration.html#disallowed-methods).

The dependency policy retains rustls and rejects native TLS additions without
review. Existing MPL-2.0 HTML/CSS parser dependencies have exact package/version
exceptions; new licenses and sources fail closed. Duplicate transitive versions
remain review warnings, avoiding artificial upgrades across incompatible majors.

### Preserve lifecycle guarantees and state their limits

Observed: `lib/runtime-process` hides an overall deadline across stdin, both output
pipes and child observation, with process-group cleanup and cancellation ownership.
Multiple callers justify that shared interface. Tokio exposes process-group and
child-drop controls, but does not supply the whole contract automatically. Source:
[Tokio process commands](https://docs.rs/tokio/latest/tokio/process/struct.Command.html).

A deadline is not a memory bound: current capture uses `read_to_end` on both
pipes. Callers with large or untrusted output need explicit bounded capture or
streaming. Choosing a global arbitrary limit would change behavior and requires
caller-specific contracts. Source:
[Tokio reading](https://docs.rs/tokio/latest/tokio/io/trait.AsyncReadExt.html#method.read_to_end).

Temporary-file persistence provides atomic replacement, not automatic crash
durability. Keep permission, no-clobber, symlink, locking and directory-sync policy
with the owning feature instead of introducing a generic writer around differing
contracts. Source:
[tempfile persistence](https://docs.rs/tempfile/latest/tempfile/struct.NamedTempFile.html#method.persist).

## Validation and limits

This investigation inspected manifests, runtime packaging, shared process handling
and representative archive, preference and native-validator code. Official
sources were retrieved on the review date. No production operations or Darwin
linking/callback tests ran. Native Linux implementation validation passed the sandboxed `rust-quality`
gate (rustfmt, all-target Clippy, rustdoc warnings, offline dependency policy),
the live advisory scan and retained Nix library cases. Darwin check names
evaluated successfully; native Darwin compilation and execution did not run. No claim establishes whole-workspace runtime correctness,
ABI safety or measured speed/memory improvements.

## Implication for this repository

Implement quality/dependency gates with pinned Nix tools; remove redundant
source/check inventories; ensure adapter lint coverage; preserve feature-local
runtime behavior and platform contracts. Resource caps and crash durability need
explicit caller contracts before changing their runtime semantics.
