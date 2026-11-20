# Testing and static checks

Use the pinned `nix-unit` runner for functions in `lib/`. Each repository owns
its own library suite; nix-seal uses `nix/lib/tests` and also retains Rust tests.
Other project-authored behavioral, integration, VM, snapshot and non-Rust fuzz
suites are not part of this project. Upstream package test defaults remain intact.

```sh
just test
nix develop --command nix-unit --flake '.#libTests'
nix build --no-link .#checks.x86_64-linux.lib-tests
just check
```

Replace the system for the native platform. New source files must be visible to
Git before flake evaluation. `git add -N <file>` includes a new file in the source
view without staging its contents. Tests under `lib/tests` import actual library
functions explicitly; production imports must not recursively load their fixtures.

Cases use named `expr`/`expected` values and `expectedError` for library rejection
contracts. The runner fails through its exit status; no hand-written assertion
wrapper is needed. A derivation constructor in `lib/` does not authorize keeping
an application runtime or package integration suite.

Keep static formatting, lint, syntax, type, schema, documentation and security
analysis. The authoritative configuration is in `flake/dev/formatter.nix`,
`flake/dev/git-hooks.nix`, `flake/dev/checks.nix` and
`flake/dev/javascript-checks.nix`. `nix develop --command javascript-check`
runs compiler, lint and formatting checks with Nix-managed tools and declarations.
`runtime-source-policy` rejects reintroducing root-owned Python, C, AWK and Tcl programs.

## Rust workspaces

Initialize the submodules with `git submodule update --init --recursive` when
setting up a fresh checkout. `nix develop .#ciRust --command rust-workspaces list`
shows the discovered workspace roots, including nix-seal's independent legacy
and fuzz manifests.

| Command | Checks |
| --- | --- |
| `just rust-check` | rustfmt, native all-target Clippy, rustdoc, cargo-machete, cargo-deny bans/licenses/sources, and Semgrep on first-party Rust. CI runs the same command through the pinned shell. |
| `just rust-audit` | Fresh RustSec advisory checks for each workspace using its own lockfile and policy. CI runs this separately. |
| `just rust-analyze` | rust-analyzer batch statistics for each workspace. Cargo fetches locked dependencies before offline analysis. Add `--verbose` for per-item statistics or `--diagnostics` for IDE diagnostics. |
| `just rust-test` | Nextest for native unit and integration tests, including nix-seal's legacy migration suite. Cargo runs doctests separately. The fuzz targets use their dedicated suite. |

Open the root in VS Code from the development environment to use the pinned
toolchain with all four linked projects. When adding a workspace, update
`.vscode/settings.json` and run `just rust-check` to verify the list. Native
compiler checks use the runtime registry's platform support. Run on Darwin for
Darwin compiler diagnostics.

Rust-analyzer reports limits in its own MIR lowering, layout and constant
evaluation. Use the verbose output to identify the affected item and confirm
suspected source errors with the locked Cargo checks.
The diagnostics command returns failure when the analyzer reports errors. The
vendored `age` localization wrapper preserves compile-time Fluent validation
and works around an analyzer macro-expansion bug.
[Upstream diagnostic report](https://github.com/rust-lang/rust-analyzer/issues/23502)

The root flake also exposes the sandboxed `rust-quality` check through
`just check`. It uses the Cargo member fileset, Nix-vendored dependencies and
offline cargo-deny policy. Each submodule retains its own CI and native checks.
When changing Rust policy in a submodule, publish its changes with the matching
gitlink update so a fresh CI checkout sees the same policy.

See the [workspace research](research/rust-workspace-checks-research.md) for tool
coverage and the [Rust design research](research/rust-quality-design-research.md)
for the root packaging and runtime design.

### Coverage, mutation, and inspection

Enter `nix develop .#rustAnalysis` for the stable analysis tools. It uses the same
compiler and native libraries as the workspace checks.

| Tool | Use |
| --- | --- |
| cargo-llvm-cov | `just rust-coverage` runs nix-seal's regular Nextest suite and writes `nix-seal/target/coverage.lcov`. The shell supplies the LLVM profile readers from the compiler's LLVM release. |
| cargo-mutants | `just rust-mutate-core "$(mktemp -d)"` and `just rust-mutate-policy "$(mktemp -d)"` run their respective campaigns on temporary source copies that exclude ignored files, including nested Cargo build directories. Kani proof code is checked separately with `just rust-kani`. |
| cargo-geiger | Run `rust-unsafe-inventory path/to/package/Cargo.toml` with a concrete package manifest. It requires the existing workspace lockfile, uses fresh Cargo artifacts, and rejects incomplete scans. Unsafe counts are an inventory for review. |
| cargo-expand | Run `cargo expand --locked --lib --package nix-conf-legacy-numbers` to inspect macro expansion for a selected crate. |
| cargo-flamegraph | Profile a repeatable local workload with debug symbols. The nix-seal scale benchmark uses synthetic inputs. See the Linux example below. |
| sccache | Run `just rust-cached check --locked --package nix-conf-legacy-numbers` and inspect `sccache --show-stats` in the analysis shell. This opts in for one Cargo command and disables incremental compilation for that command. |

For compiler diagnostics from one library build, run
`cargo rustc --locked --manifest-path path/to/package/Cargo.toml --lib -- --force-warn unsafe_code`.
This applies the lint to the selected library, including its expanded code.
The warnings do not establish completeness of a Geiger inventory.

For a Linux CPU profile, run the following from the checkout root inside the
analysis shell. The output directory also contains the raw perf capture. Perf
needs permission to sample user-space events on the host.

```bash
(
  set -euo pipefail
  perf stat -e cpu-clock:u -- true
  profile_dir=$(mktemp -d)
  cd nix-seal
  export RUSTC_WRAPPER= RUSTC_WORKSPACE_WRAPPER=
  export CARGO_PROFILE_BENCH_DEBUG=line-tables-only CARGO_PROFILE_BENCH_STRIP=none
  benchmark=$(cargo bench --locked -p nix-seal-policy --bench scale --no-run \
    --message-format=json-render-diagnostics |
    jq -er 'select(.target.name == "scale" and .executable != null) | .executable')
  cd "$profile_dir"
  flamegraph --cmd 'record -e cpu-clock:u -F 99 -g' --deterministic \
    --output scale.svg -- "$benchmark" --size 10000
  printf '%s\n' "$profile_dir/scale.svg"
)
```

### Miri and Kani

Use `nix develop .#rustVerification` for the verifiers. `just rust-miri` interprets
`nix-seal-core` unit tests with the pinned nightly and matching standard-library
source. Select other compatible tests explicitly with `cargo miri test`.

On Linux and macOS, `just rust-kani` checks all 256 byte values against the
identifier alphabet using Kani and the compiler matched to that release.
Unit tests cover the parser's segment structure and preservation of spelling.

## Nix configuration and native verification

Module `assertions` reject invalid setting combinations at configuration evaluation.
They must not freeze arbitrary host choices. Production input errors, strict
rendering, activation preflight and runtime safety checks remain normal behavior.
Assertions outside modules are not a substitute for the library runner.

Run retained checks relevant to a change and report the tested platforms. Library
and static checks do not prove service operation, VPN confinement or backup
restoration. Native Darwin checks require Darwin. A full desktop closure build,
when needed, must run on desktop as described in [AGENTS.md](../AGENTS.md).

The [framework research](research/testing-frameworks-research.md) records the runner choice.
