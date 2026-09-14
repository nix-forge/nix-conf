# Testing

Use the framework that exercises the behavior at its owning repository. Root
Python tests run through pytest. Nix evaluation, generated-file validation, and
NixOS VM tests remain Nix checks. Package tests, Cargo tests, and Swift XCTest
retain their own runners. The [framework research](testing-frameworks-research.md)
explains the choice and alternatives.

## Commands

Run from the repository root with initialized submodules. New source files must
be visible to Git before flake evaluation. `git add -N <file>` includes a new file
in the source view without staging its contents.

```sh
just test-python
just test-python tests/codex -q
just test-ci
workstation-task nix build --no-link .#checks.x86_64-linux.python-tests
workstation-task nix build --no-link .#checks.x86_64-linux.secret-templates
workstation-task nix build --no-link .#checks.x86_64-linux.git-email-privacy
just generated-checks
```

The named build examples use the desktop workload runner. On other hosts, run
`nix` directly and replace the system for the supported platform. The focused
`tests` development shell supplies Python and command dependencies without
installing hooks. Both local and sandbox runs use the dependencies in
[the Python environment](../flake/dev/test-python.nix) and settings in
[pyproject.toml](../pyproject.toml). Tests time out after 120 seconds; a documented
longer bound belongs on a specific test, rather than disabling the limit globally.
Unexpected passes of tests marked `xfail` fail the suite.

Default pytest discovery selects `tests/**/test_*.py`. It excludes two explicit
markers:

- `nix_integration` needs generated inputs supplied by `secret-templates` or
  `git-email-privacy`. Those checks run their complete selected suites and store
  a JUnit report in the output directory. Missing inputs fail the check.
- `nix_daemon` runs with `just test-ci`, outside a Nix build sandbox. These tests
  use disposable Git history and Nix evaluation. The shell supplies immutable
  Nixpkgs and framework input paths, avoiding repeated whole-flake resolution.

Deselection is a declared execution boundary, not evidence of a pass. Inspect
all collected cases with `just test-python --collect-only -m ''`. Ordinary CI
check discovery includes `python-tests`, secret and privacy integration, and
platform-specific checks. The CI workflow runs daemon tests separately.

## Layout and ownership

| Location | Contract and execution |
| --- | --- |
| `tests/browsers`, `tests/codex`, `tests/macos` | Public helper commands, unmanaged settings, permissions, and idempotence. Included in `python-tests`. |
| `tests/fonts` | Composition examples in pytest; real selection, shaping, and native rendering remain font checks. |
| `tests/hyprland/test_*.py` | Isolated runner environment, cleanup, and crash reporting. No compositor connection. |
| `tests/storage/test_*.py` | Recovery receipts, backup preconditions, and real disposable Restic backup/restore. Included in `python-tests`. |
| `tests/virtualisation` | Installer rendering and libvirt command contracts using temporary state. Real XML and JSON tools, with explicit guest adapters. Included in `python-tests`. |
| `tests/maintenance` | Root command delegation against disposable package scripts. Included in `python-tests`. |
| `tests/secrets`, `tests/git_privacy` | Identity rollback, policy evaluation, generated templates and generated Git hooks. Rollback is portable; generated inputs have dedicated checks. |
| `tests/ci` | Build selection, target discovery, and deployment exclusions using real Git/Nix. |
| `tests/nix` | Evaluated configuration, generated artifacts, writer rejection tests, and the ClamAV VM. |
| `tests/storage/install.nix` | Disposable disk installation, boot and restoration. Requires native x86 Linux with virtualization. |
| `flake/dev/local-control-checks.nix` | Local-control process, filesystem, proof and activation checks. Darwin-only checks are absent on Linux, rather than successful placeholder builds. |
| `tests/{browsers,hyprland,noctalia,systemd,terminals,codex,vscode}/check_*` | Explicit rendering and operator probes with their own arguments and environment requirements. Some run from dedicated Nix checks; none are implicitly collected by pytest. |
| `tests/lua`, native font sources | Native-language checks invoked by their owning Nix derivations. |
| Submodule `tests`, package-local `Tests`, Rust test modules and fuzz targets | Owned and validated in the submodule. Root pytest does not recurse into them. |

`flake/dev/python-checks.nix` defines the portable sandbox source and dependencies.
The common [Python check builder](../tests/python-check.nix) copies selected
sources to writable scratch space, supplies an isolated home, applies pytest
policy, and writes JUnit output. It does not contain a second test runner.
Add fixture files and production sources to the source set when a new test needs
them. New Python tests under `tests/` are discovered automatically.

Python lint and type checks use a separate, broader import environment in
[`quality-python.nix`](../flake/dev/quality-python.nix). The sandbox check and
local Git hook share it, including the documentation builder's dependencies.

Keep fixtures next to their feature. Use a local `conftest.py` only for shared
setup with a real consumer. The CI Git fixture clears inherited identity,
signing, hook and repository settings. Avoid repository-wide implicit fixtures
that change unrelated tests.

## What a test must prove

Start with a named behavior that can regress. Cross the same command or function
interface as a caller. Compare outputs, exit status, parsed configuration, file
state, or externally visible service behavior. Give negative cases an explicit
expected failure and verify that protected state remains intact.

Use an independent fixture for expected values. Do not assert properties of
locally declared fixture constants, compare a function with itself, repeat a
production inventory in the test, or search source text when execution can prove
the requirement. Exact bytes remain appropriate for preservation, wire formats,
signatures, and executable headers.

Prefer pytest functions, `tmp_path`, `monkeypatch`, and named parameter examples
for new Python tests. Existing `unittest.TestCase` suites remain valid under
pytest; converting assertion syntax alone adds no coverage. Mock an unavailable
external service or unsafe effect, then use real local parsers and filesystem
operations. Unexpected adapter calls must fail, not silently succeed.

Use `lib.runTests` with named expressions and expected values for pure Nix
contracts. Force and report its failure list. Nix module `config.assertions` are
lazy: checks that only read selected options must explicitly force the relevant
assertions. A derivation path alone does not prove those assertions passed.

VM tests must wait for observable readiness, bound retries, and distinguish old
state from recovery. Keep installer disks and service fixtures disposable. The
ClamAV fixture tests systemd ordering and namespace visibility, not antivirus
detection. Backup receipts alone do not prove restoration; retain the real
Restic round trip.

A passing scan must cover every candidate and surface read errors. Never use an
early-exiting consumer under `pipefail` to decide whether a producer found a
match. Scanner regression tests include clean input, many matches, binary files,
missing input, and unreadable files.

## Review decisions

The September 2026 review retained behavior tests for writers, schema rejection,
privacy hooks, backup restoration, native rendering, local-control validation,
and VM integration. These test distinct contracts. Operational probes remain
explicit because they require native applications, hardware, or a live session.

The revision removed separate root unittest launchers and duplicate portable
execution from font, generated-file and deployment checks. CI tests and the
VM-host resolver fixture moved under `tests/`. Previously manual appearance
configuration tests now run automatically through the production CLI.

The review also removed fixture-only policy assertions, exact child-kill call
ordering, a probabilistic race loop that accepted every read error, a fake XML
parser, silent command substitutions, and Linux readiness source-string
assertions. Their replacements exercise policy results, owned
process cleanup, real parsing, failed unexpected calls, and generated preflight
execution. Secret-template policy failures now report named Nix cases.

Submodule fixes address an unchecked framework assertion, nix-seal's store-scan
false negative and readiness control flow, and OCR test lock isolation. Rust
canary checks now use the actual secret length. Batch replacement checks require
both outputs and decrypt the expected destinations. Invalid-path and identity
collision fixtures start from valid inputs, so an unrelated error cannot satisfy
the test. Shell fixture assertions propagate failures. Removed assertions compared
a function with itself or tested only standard-library behavior.

Keep these patches with their owning repositories when committing. A root
gitlink alone cannot represent uncommitted submodule changes.

The review read root test suites and their Nix entry points, all package Python
suites and native fixtures, the complete framework suite, nix-seal's Nix and VM
checks, and every Rust test body under nix-seal's crates and the root filesystem
helper. It also read the operational desktop probes. Cargo, interoperability,
migration-golden and fuzz tests retain their existing structure.

The filesystem helper tests call the actual reader and atomic writer to check
symlink rejection and preservation of unsafe targets. Temporary fixture paths
are canonicalized so macOS's `/tmp` compatibility symlink does not invalidate
the fixture itself.

Desktop probes bound debugger startup and IPC waits, clean up owned children on
failure, and keep diagnostics from bypassing cleanup. The stopwatch fixture also
clears shell startup environment variables. VS Code's CLI detaches its GUI;
if startup fails before the debugger connects, its isolated test window may need
to be closed manually. These probes remain opt-in.

## Evidence boundaries

Run focused tests before broad checks. Record evaluation, build, VM execution,
and live activation separately. Full desktop builds must follow
[AGENTS.md](../AGENTS.md). Native Darwin tests need Darwin; GUI, HDR and physical
output probes need their declared environment. Neither a Linux pass nor an
absent platform check establishes those results.

Do not add tests for every configuration assignment or require a coverage
percentage without a decision it supports. Add cases for meaningful failure
modes and remove tests whose only effect is to freeze an implementation detail.
For a repaired test that previously passed incorrectly, demonstrate that a
controlled broken implementation now fails.
