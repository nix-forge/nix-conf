# Rust checks across independent workspaces

Reviewed 2026-11-18 on x86_64 Linux. Scope includes the root checkout and
recursive Git submodules.

## Answer

Run the same first-party checks from each Cargo workspace root. Use the Git
inventory, Cargo's workspace resolution and the pinned Nix shell. Keep each
workspace's lockfile, features, compiler options and dependency policy with
its owner. Keep the root's existing sandboxed check for reproducible builds
and run live advisory refreshes separately.

## Findings and sources

- Cargo workspaces share a lockfile, output directory, lints and patch resolution.
  One new parent workspace would couple the existing independent dependency
  graphs. Discover manifests from Git and resolve them with
  `cargo locate-project --workspace`. The current inventory is the root
  workspace plus the main, legacy and fuzz workspaces in nix-seal. The other
  initialized submodules currently have no Rust crates.
  [Cargo workspaces](https://doc.rust-lang.org/cargo/reference/workspaces.html),
  [Cargo locate-project](https://doc.rust-lang.org/cargo/commands/cargo-locate-project.html).
- Clippy and rustdoc check the native target and use the platform support already
  declared by the root's Nix packaging. Clippy searches ancestors for configuration.
  nix-seal declares its own minimum Rust version for Clippy, so it also has its
  own configuration boundary when checked from a parent clone.
  [Clippy configuration lookup](https://github.com/rust-lang/rust-clippy/blob/master/clippy_config/src/conf.rs),
  [native package registry](../../flake/runtime-packages.nix).
- Cargo-machete complements compiler lints with a heuristic for unused manifest
  dependencies. The legacy manifest intentionally enables `age/ssh-rsa` for
  its shared CLI and records that feature-only edge in manifest metadata.
  Semgrep scans the explicit Git inventory of first-party Rust, including fuzz
  targets, for TLS verification bypasses, unbounded async queues and disabled
  WebSocket limits. The runner compares the scanner's reported paths with that
  inventory. Vendored age participates as a compiler and dependency-policy input.
  [Cargo-machete](https://github.com/bnjbvr/cargo-machete),
  [Semgrep pattern syntax](https://docs.semgrep.dev/writing-rules/pattern-syntax).
- Dependency policy checks use each locked graph. The fuzz harness shares
  nix-seal's license, source and ban policy with a version-specific NCSA exception
  for libFuzzer. Its advisory scan reads its independent lockfile. The legacy
  workspace retains its separate compatibility policy.
  [cargo-deny license exceptions](https://embarkstudios.github.io/cargo-deny/checks/licenses/cfg.html),
  [cargo-audit](https://github.com/rustsec/rustsec/tree/main/cargo-audit).
- rust-analyzer supports multiple linked Cargo projects in one editor session.
  The batch command runs separately in each workspace and reports inference
  statistics. The pinned toolchain supplies matching standard-library source
  and Cargo, including when rust-analyzer invokes a Rustup proxy.
  [rust-analyzer configuration](https://rust-analyzer.github.io/book/configuration.html),
  [tool discovery in the tested release](https://github.com/rust-lang/rust-analyzer/blob/2026-11-02/crates/project-model/src/sysroot.rs).
- Use Nextest for the workspaces' libtest suites and Cargo for doctests. The custom
  scale benchmark and specialized Miri, sanitizer, mutation and fuzz runs have
  project-owned inputs and workflows. Formal proofs and coverage would require
  a defined set of harnesses and test expectations for each new target.
  [Nextest running tests](https://nexte.st/docs/running/),
  [nix-seal contributor guide](../../nix-seal/CONTRIBUTING.md),
  [Kani proof harnesses](https://model-checking.github.io/kani/).

## Initial validation and limits

On x86_64 Linux, the checkout checks passed for all four workspace roots.
Semgrep scanned 141 first-party Rust files, and a temporary fixture exercised
all three rules. The four advisory scans and the root sandboxed check passed.
Nextest passed 229 regular tests and one legacy migration test.

Batch rust-analyzer loaded all four roots with native Cargo settings. Its root
statistics included 183 MIR lowering failures, three data-layout failures and
one constant-evaluation failure. Clippy and rustdoc supplied the compiler
diagnostics. Darwin validation was evaluation only.

## Opt-in analysis and verification

The stable analysis shell inherits the workspace-check compiler and native
dependencies. It exports that compiler's LLVM profile readers for cargo-llvm-cov.
Miri uses a dated nightly with matching Rust sources. Kani uses a fixed-output
release archive and the nightly recorded in that archive. The verification
shell selects these compilers independently of the stable build.
[cargo-llvm-cov](https://github.com/taiki-e/cargo-llvm-cov),
[Miri](https://github.com/rust-lang/miri),
[Kani release](https://github.com/model-checking/kani/releases/tag/kani-0.68.0).

On x86_64 Linux, coverage produced LCOV from 229 nix-seal tests and Miri passed
two core tests. A disposable proof ran through Kani and CBMC. A separate fixture
produced a complete Geiger report and detected a mutation. Geiger 0.14.0 also
reported dependency parse gaps on a real workspace graph. The inventory command
returns failure in that case. Macro expansion succeeded on a root library,
flamegraph sampled the synthetic scale benchmark, and a second cached compile
recorded a Rust cache hit.

## Follow-up on incomplete results

- The local check and audit passed across all four workspace roots. Semgrep
  scanned 150 first-party Rust files. The native test runner compiled the root
  workspace's test targets and found zero cases. It ran 258 nix-seal tests and
  one legacy migration test successfully. The same 258 regular tests produced
  LCOV with matching LLVM profile readers. The generator-worker test directs its
  instrumented child to the coverage runner's output directory.
- Verbose analysis attributed 158 of the root's 183 failed MIR bodies to
  unsupported async constructs in rust-analyzer and the other 25 to bodyless
  foreign declarations. Its three layout failures
  involved constants the analyzer could not evaluate. All four Cargo graphs
  passed compiler checks with default and all features. `just rust-analyze
  --verbose` exposes the analyzer's per-item reasons while retaining the same
  workspace coverage. [Pinned MIR lowering](https://github.com/rust-lang/rust-analyzer/blob/2026-11-02/crates/hir-ty/src/mir/lower.rs#L95-L130)
  · [Analysis statistics](https://github.com/rust-lang/rust-analyzer/blob/2026-11-02/crates/rust-analyzer/src/cli/analysis_stats.rs).
  `just rust-analyze --diagnostics` runs the IDE diagnostics across the same
  workspace roots. Six distinct first-party hints were fixed. The root
  initially reported zero errors, while each nix-seal workspace reported 64
  errors from valid `age` localization macros. The tested 2026-11-16 release
  reproduced them. Moving the hygienic loader path into a Rust binding cleared
  the errors on calls without arguments. Forwarding argument tokens through
  the wrapper macros cleared the remaining failures. The patched vendored
  source produced zero IDE errors in all four workspaces with the pinned
  analyzer. Cargo and rust-analyzer still rejected a nonexistent translation
  key in a disposable copy. The compiler checks and 259 Nextest tests passed,
  and the vendor inventory matched its recorded hashes.
  The separate statistics command still reports 183 failed MIR bodies at the
  root and 1, 9, and 9 in the main, fuzz, and legacy nix-seal workspaces.
  [Analyzer release](https://github.com/rust-lang/rust-analyzer/releases/tag/2026-11-16)
  · [Upstream macro issue](https://github.com/rust-lang/rust-analyzer/issues/23502).
- Geiger 0.14.0 parses files from wider workspace metadata before reporting on
  the selected build. The observed failures included two out-of-graph Rust 2015
  crates and missing attribution for generated Rust. A narrower unit-graph probe
  excluded both unrelated crates and parsed the generated Rust successfully.
  The wrapper isolates Cargo artifacts and rejects incomplete inventories. It
  includes packages and build inputs that lack metrics in its diagnostics. A
  complete scanner fix needs unit-based package selection and input attribution,
  including generated Rust and files included as data. [Geiger file discovery](https://github.com/geiger-rs/cargo-geiger/blob/118a9a2812098ad757c9174ad00be21deaea7e0d/cargo-geiger/src/scan/find.rs#L78-L116)
  · [Cargo unit graph](https://github.com/rust-lang/cargo/blob/f2d3ce0bd7f24a49f8f72d9000448f8838c4e850/src/cargo/core/compiler/unit_graph.rs#L16-L43).
  The wrapper also locks Geiger's external Cargo metadata call. With pinned
  Geiger and Cargo, it rejects missing or stale lockfiles without creating or
  modifying them, rejects non-singleton JSON reports, and accepts a complete
  one-package fixture. Rustc emitted identical dependency entries for code and
  data includes of the same filename. Reporting those accurately requires
  information that Geiger's dependency files currently lack.
  [Compiler dependency tracking](https://github.com/rust-lang/rust/blob/58cf8f9c35b355199727627d07ae34a4e2846d67/compiler/rustc_interface/src/passes.rs#L594-L654).
  Upstream HEAD still matches 0.14.0. Open PR #579 attributes generated `.rs`
  files more precisely and limits collection to current dep-info artifacts.
  Its extension filter can omit Rust included from `generated.inc` and count
  text loaded from `payload.rs`. In a pinned fixture, Rustc produced identical
  dep-info for `include!`, `include_str!`, and `include_bytes!` using the same
  path. Exact attribution requires knowing how each compilation unit consumes
  the input. The wrapper continues to reject incomplete inventories.
  [Geiger release](https://github.com/geiger-rs/cargo-geiger/releases/tag/geiger-0.14.0)
  · [Proposed upstream fix](https://github.com/geiger-rs/cargo-geiger/pull/579)
  · [Extension filter](https://github.com/geiger-rs/cargo-geiger/blob/a5fb768541cd1fe5cbefe9e7c5cb55353822cf4b/cargo-geiger/src/scan/find.rs#L180-L208).
  For a selected library, the compiler's `unsafe_code` lint provides evidence
  from expanded code. A fixture reported unsafe functions from an included
  `.inc` file and a macro expansion while the file included as text produced
  no warning. The lint reports diagnostics for that build and has exemptions
  for internal compiler spans. Geiger's package-level metrics have a different
  scope. [Lint levels](https://doc.rust-lang.org/rustc/lints/levels.html#force-warn)
  · [Compiler lint implementation](https://github.com/rust-lang/rust/blob/58cf8f9c35b355199727627d07ae34a4e2846d67/compiler/rustc_lint/src/builtin.rs#L193-L219).
- The core mutation campaign exposed gaps in identifier spelling, path length,
  generator defaults, and runtime override tests. Those cases now check the
  production interfaces. The rerun caught 37 buildable mutants and found three
  that could not compile. The policy baseline had 196 survivors. A survivor
  rerun caught 28 after adding loader, schema, and name-grammar tests. Ten more
  were caught by strengthening the canonical serialization and hash tests.
  Tests for field formats, time and execution limits, and generator graph and
  prompt validation caught another 66, leaving 92 survivors at that stage.
  The next round added 17 tests for boundary values, recipient and target
  selection, approval policy, and generator validation. It also reused resolved
  consumers and consolidated built-in generator output validation. The full
  campaign caught 398 of 411 candidates. Twelve could not compile and one
  survived. That mutation changes a defensive threshold guard in the approval
  projection. The public entry point validates explicit policies against the
  distinct signer count and ensures a signer exists for the default threshold,
  so the projected threshold is valid in both versions. The guard is retained.
  The local mutation recipes honor Git ignores to keep the legacy and fuzz
  build directories out of campaign copies.
  [cargo-mutants build directories](https://mutants.rs/build-dirs.html).
  The Kani proof checks the identifier alphabet for all 256 byte values. Native
  Apple Silicon execution passed Miri, the proof, and the root sandboxed Rust
  gate after adapting Kani's compiler packaging. The same four Miri tests and
  the proof passed on x86-64 Linux, on native ARM Linux, and under ARM Linux
  emulation.
  [Core tests](../../nix-seal/crates/nix-seal-core/src/lib.rs)
  · [Kani proof](../../nix-seal/crates/nix-seal-core/src/proofs.rs)
  · [Kani linker invocation](https://github.com/model-checking/kani/blob/kani-0.68.0/kani-driver/src/call_goto_cc.rs).

## Choosing age and rage

Prefer the Go `age` CLI for general-purpose file encryption and keep both CLIs
as nix-seal interoperability test peers. The Go release examined was 1.3.2,
which includes input hardening. The Rust CLI release was `rage` 0.12.1. They
implement the same age format, with capabilities that vary by release. Keep
recipients within nix-seal's supported set for shared files.
[age 1.3.2](https://github.com/FiloSottile/age/releases/tag/v1.3.2)
· [rage 0.12.1](https://github.com/str4d/rage/releases/tag/v0.12.1)
· [age format](https://age-encryption.org/v1).

Keep the reviewed Rust `age` library for nix-seal's in-process encryption.
The `rage` binary depends on that library. Selecting the binary as a backend
would introduce a subprocess and move recipient and identity handling across
that boundary. The vendored Rust library preserves the reviewed recipient
surface, with RSA confined to the offline legacy build. Reassess vendoring
when a released Rust `age` library satisfies those compatibility and dependency
checks. The Go CLI release does not update the Rust dependency graph.
[rage manifest](https://github.com/str4d/rage/blob/v0.12.1/rage/Cargo.toml)
· [Rust age release](https://docs.rs/crate/age/0.12.1)
· [Dependency decision](../../nix-seal/docs/adr/0030-dependency-surface-remediation.md)
· [RSA decision](../../nix-seal/docs/adr/0031-isolated-rsa-migration-build.md).

The Nix package supplies both CLIs as check inputs. The X25519 interoperability
test exercises encryption and decryption between nix-seal and each binary in
both directions. It passed on x86_64 Linux on 2026-11-18 with `age` 1.3.2 and
`rage` 0.12.1. That evidence is specific to X25519 and the tested releases.
[Package check inputs](../../nix-seal/flake/production.nix)
· [Interoperability test](../../nix-seal/crates/nix-seal-crypto/src/lib.rs).
