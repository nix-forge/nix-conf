# Quality checks for the WireGuard roaming controller

Research date: 2026-09-02

## Decision

Use stable Rust and the pinned Nixpkgs toolchain for every required check. The
release gate should contain `cargo fmt`, `cargo check`, strict Clippy, Cargo's
test runner, and the deterministic parts of `cargo-deny`. Run the current
RustSec advisory check as a separate networked CI job. Do not make nextest,
Miri, sanitizers, fuzzing, coverage, or semantic-version checks release gates
for this package today.

This is a small, private, macOS-only binary with 21 unit tests and three direct
Rust dependencies. More tools would not automatically make it safer. The best
next step is to close the few real gaps in the current setup, then keep each
required command reproducible through Nix.

## Existing baseline

The package already gets most of this right:

- `Cargo.toml` selects Rust 2024, declares Rust 1.97 as its minimum version,
  forbids unsafe code, enables Clippy's `all` and `pedantic` groups, and denies
  `unwrap`, `expect`, and `panic`.
- `package.nix` uses `buildRustPackage`, imports a committed `Cargo.lock`,
  restricts the Nix source to the manifest, lockfile, and Rust source, and runs
  rustfmt, strict Clippy, and tests in the sandbox.
- The root development shell supplies Cargo, rustc, rustfmt, Clippy,
  `cargo-audit`, `cargo-deny`, and Darwin's `libiconv`. VS Code runs Clippy on
  all targets and formats Rust on save.
- The `nixpkgs-personal` treefmt setup already applies rustfmt to Rust, Taplo to
  TOML, and `nixfmt`, Statix, deadnix, and nixf diagnostics to the Nix package
  expression.

Relevant repository files are
[`Cargo.toml`](../pkgs/pkgs/by-name/wi/wireguard-roaming-controller/Cargo.toml),
[`package.nix`](../pkgs/pkgs/by-name/wi/wireguard-roaming-controller/package.nix),
the [`nixpkgs-personal` formatter configuration](../pkgs/flake/dev/formatter.nix),
and its [development shell](../pkgs/flake/dev/shell.nix).

## Required checks

| Check | Required command or policy | Why it belongs in the gate |
| --- | --- | --- |
| Formatting | `cargo fmt --all -- --check` | rustfmt is the standard Rust formatter. Add a small `rustfmt.toml` with `edition = "2024"` and `style_edition = "2024"` so direct editor invocations and `cargo fmt` use the same edition. The rustfmt project recommends setting both values explicitly. ([rustfmt](https://github.com/rust-lang/rustfmt), [Rust 2024 style edition](https://doc.rust-lang.org/edition-guide/rust-2024/rustfmt-style-edition.html)) |
| Type checking | `cargo check --locked --all-targets` | This is Rust's explicit fast type-checking command. Cargo notes that it skips final code generation, so the package build and test link must still run. `--locked` rejects a missing or changed lockfile instead of resolving a different graph. ([`cargo check`](https://doc.rust-lang.org/cargo/commands/cargo-check.html), [`--locked`](https://doc.rust-lang.org/cargo/commands/cargo-test.html#manifest-options)) |
| Rust lints | `cargo clippy --locked --all-targets -- -D warnings` | Clippy recommends `-D warnings` for CI. Keep `all` and `pedantic`, plus selected restriction lints. Clippy explicitly warns against enabling the entire `restriction` or `nursery` groups. ([Clippy usage](https://doc.rust-lang.org/stable/clippy/usage.html), [lint groups](https://doc.rust-lang.org/clippy/lints.html)) |
| Tests | `cargo test --locked --all-targets --no-fail-fast` | Cargo builds and runs unit and integration test targets. `--no-fail-fast` preserves later test-binary results after one binary fails, which is cheap future-proofing even though this package currently has one binary target. ([`cargo test`](https://doc.rust-lang.org/cargo/commands/cargo-test.html)) |
| Dependency policy | `cargo deny check licenses bans sources` | These checks are based on committed manifests, the lockfile, and dependency source metadata. They can run without fetching a changing advisory database. Cargo-deny checks licenses, duplicate or banned crates, and dependency origins. ([cargo-deny checks](https://embarkstudios.github.io/cargo-deny/checks/), [source policy](https://embarkstudios.github.io/cargo-deny/checks/sources/)) |
| Package build | the `buildRustPackage` derivation | Nix vendors the locked dependency graph, blocks undeclared network access, links the real macOS binary, and runs package checks. Nixpkgs documents that `buildRustPackage` enables tests by default and normally tests in release mode. ([Nixpkgs Rust manual](https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/rust.section.md)) |

Keep `runHook preCheck` and `runHook postCheck` if the package retains a custom
`checkPhase`. A better Nix integration is to run formatting, checking, Clippy,
and deterministic cargo-deny policy in `preCheck`, then let the standard
`cargoCheckHook` run tests in the same release mode Nixpkgs uses for the built
artifact. Either arrangement is acceptable if the final test command stays
locked and the Nix build proves that the executable links.

## Lint policy

Retain the current manifest policy and add only restrictions with a direct
failure mode for this daemon:

- deny `clippy::dbg_macro`, `clippy::todo`, and `clippy::unimplemented` so
  placeholder code cannot enter the root service;
- deny `clippy::allow_attributes_without_reason`; the three current local
  allows already have specific reasons;
- deny rustc's `unused_crate_dependencies` while this remains one binary with
  three ordinary dependencies; and
- deny rustc's `let_underscore_drop`, which makes intentionally discarded
  guard and `Result` values explicit.

Rustc documents `unused_crate_dependencies` as allow-by-default and warns that
multi-target packages can need explicit accommodations. Revisit it if this
package gains a library, examples, or target-specific development dependencies.
`let_underscore_drop` belongs here because the controller relies on RAII for
files and locks. ([rustc allow-by-default lints](https://doc.rust-lang.org/stable/rustc/lints/listing/allowed-by-default.html),
[rustc lint groups](https://doc.rust-lang.org/rustc/lints/groups.html))

The existing `rust-version = "1.97"` also supplies Clippy's MSRV setting. Cargo
uses this field for compatibility diagnostics and dependency resolution, while
Clippy suppresses or changes suggestions that are unavailable at that version.
Keep the Nixpkgs compiler at Rust 1.97 or later, and test the declared minimum
before raising it. ([Cargo `rust-version`](https://doc.rust-lang.org/cargo/reference/rust-version.html),
[Clippy MSRV](https://doc.rust-lang.org/stable/clippy/lint_configuration.html#msrv))

Do not add an unpinned rustup-managed toolchain inside the Nix build. The flake
lock already pins Nixpkgs and therefore the compiler, Cargo, rustfmt, and
Clippy versions used by CI.

## Dependency and advisory policy

Add a crate-local `deny.toml` with version 2 tables and this policy:

- allow `MIT` and `Apache-2.0`; `Apache-2.0 WITH LLVM-exception` may also be
  listed explicitly, although every current dependency that offers it also
  offers MIT or plain Apache-2.0;
- deny wildcard requirements;
- deny multiple versions because the current graph has none, with future
  exceptions documented by crate and reason;
- deny unknown registries and unknown Git sources; and
- deny yanked packages and do not add blanket advisory exceptions.

Cargo-deny treats its checks as separate policy classes and supports explicit
lint levels and narrow exceptions. Its license check evaluates SPDX
expressions but does not replace review of the actual license files. That
limitation matters when accepting a new dependency. ([cargo-deny license
configuration](https://embarkstudios.github.io/cargo-deny/checks/licenses/cfg.html),
[bans configuration](https://embarkstudios.github.io/cargo-deny/checks/bans/cfg.html),
[source configuration](https://embarkstudios.github.io/cargo-deny/checks/sources/cfg.html))

Current vulnerability data cannot be a reproducible Nix derivation unless the
advisory database is pinned, at which point it stops being current. Run one
networked advisory command on lockfile changes and on a schedule:

```console
cargo deny check advisories
```

Using `cargo audit --deny warnings` instead is also sound, but running both as
required gates duplicates the same RustSec database. RustSec describes
`cargo-audit` as a `Cargo.lock` scanner, while cargo-deny consumes the same
database and adds the policy checks above. ([RustSec advisory database](https://github.com/RustSec/advisory-db),
[`cargo-audit`](https://github.com/RustSec/rustsec/tree/main/cargo-audit),
[cargo-deny advisories](https://embarkstudios.github.io/cargo-deny/checks/advisories/))

For stronger supply-chain assurance, `cargo-vet` is the next meaningful step.
It records reviews of third-party source rather than checking only known
advisories and metadata. Do not initialize it with permanent blanket
exemptions and call that an audit. Adopt it only if the repository owner will
review or import trusted audits and maintain the resulting `supply-chain`
directory. ([Cargo Vet introduction](https://mozilla.github.io/cargo-vet/),
[setup and exemptions](https://mozilla.github.io/cargo-vet/setup.html))

## macOS and developer workflow

The package's own `nixpkgs-personal` development shell should include Cargo,
rustc, rustfmt, Clippy, cargo-deny, and Darwin's `libiconv`, with the same
`LIBRARY_PATH` and `NIX_LDFLAGS` treatment as the parent repository. At present,
direct `cargo test` in the ordinary shell compiles the test binary but fails to
link `-liconv`. The Nix package build is not affected because `package.nix`
declares `libiconv`; this is a developer-environment defect, not a Rust defect.

Add path-scoped pre-commit hooks in the `pkgs` submodule for rustfmt. Put
Clippy, tests, and dependency policy in pre-push or flake checks so an ordinary
commit stays quick. The parent hooks intentionally exclude submodule-owned
files, so placing these hooks only in the parent repository would leave the
package uncovered when developed or tested by itself.

Keep the full package build on `aarch64-darwin`. Linux is fine for formatting,
TOML validation, and lockfile policy, but it cannot prove that this macOS
binary links against Darwin libraries or that its target-specific system calls
compile.

## Tools that should remain optional

| Tool | Decision |
| --- | --- |
| cargo-nextest | Skip as a required gate for now. Its per-test process isolation, retries, and timeouts are useful for large suites, but 21 tests do not justify another mandatory tool. Nextest still does not run doctests, so it cannot fully replace Cargo's test command. It was run once after implementation and all 21 tests passed. ([nextest execution model](https://nexte.st/docs/design/how-it-works/), [doctest limitation](https://nexte.st/docs/integrations/test-coverage/#collecting-coverage-data-from-doctests)) |
| Miri | Developer-only, limited to pure parser and policy tests. Miri requires nightly, is much slower, does not support networking, and has incomplete platform API and FFI support. The crate also forbids first-party unsafe code, which lowers its immediate value. ([Miri](https://github.com/rust-lang/miri)) |
| AddressSanitizer and ThreadSanitizer | Optional pinned-nightly jobs, not release gates. Rust sanitizer support remains unstable. AddressSanitizer supports `aarch64-apple-darwin`, but incomplete instrumentation across Rust and native dependencies limits what it can prove. ([Rust sanitizers](https://doc.rust-lang.org/beta/unstable-book/compiler-flags/sanitizer.html)) |
| cargo-fuzz | Worth considering for the DNS snapshot, `netstat`, network service, and handshake parsers after those parsers move behind a library API. Cargo-fuzz requires nightly and an open-ended corpus run, so use bounded scheduled jobs rather than the deterministic package build. ([cargo-fuzz](https://github.com/rust-fuzz/cargo-fuzz)) |
| cargo-llvm-cov | Generate reports when coverage data will guide missing tests. Do not set an arbitrary percentage gate. The tool uses LLVM source coverage, supports macOS, and excludes doctests by default. ([cargo-llvm-cov](https://github.com/taiki-e/cargo-llvm-cov)) |
| cargo-semver-checks | Skip. It checks public library API compatibility, while this crate is `publish = false` and exposes only a binary command interface. ([cargo-semver-checks](https://github.com/obi1kenobi/cargo-semver-checks)) |

## Findings from the current tree

The following commands were run on 2026-09-02 with Cargo 1.97.0, rustc 1.97.1,
Clippy 0.1.97, cargo-deny 0.20.2, and cargo-audit 0.22.2:

- rustfmt passed;
- existing strict all-target Clippy passed;
- cargo-audit fetched 1,239 RustSec advisories, scanned all 11 locked crate
  dependencies, and reported no vulnerability, unmaintained, or yanked
  warning;
- the dependency graph contained no duplicate crate versions;
- before implementation, cargo-deny's advisory, bans, and sources checks passed
  under default policy, while its license check rejected every crate because no
  `deny.toml` license allowlist existed; the implemented license policy now
  passes for the complete dependency graph;
- the proposed extra lint set found no unused direct dependency, placeholder
  macro, unexplained allow, or debug macro;
- the discard lints found deliberate ignored results in cleanup, emergency DNS
  recovery, and handshake-probe paths. Cleanup and probe discards are now
  explicit, while DNS recovery preserves and returns the tunnel error only
  after attempting the emergency DNS reset; and
- an exploratory nursery run found only `redundant_pub_crate`, whose suggestion
  conflicts with rustc's `unreachable_pub` for private binary modules. The
  stable visibility lint remains enforced, and the full nursery group is not a
  required gate as Clippy recommends.

The required checks now live in the package derivation and local hooks, and the
same commands are available through the `nixpkgs-personal` development shell.
Current RustSec advisories run separately in CI, where the database can remain
fresh. Editors, local hooks, CI, and the final Nix build therefore share one
compiler and one policy without making a changing network database part of a
reproducible derivation.
