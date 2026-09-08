# nix-forge CodeQL review

Reviewed on 2026-09-07 from `desktop`. All five repositories returned accessible
GitHub code-scanning alert lists. There were no open CodeQL alerts. All 22
existing dismissed CodeQL alerts remain justified by the current source.

Fresh local scans found two resource-lifetime defects. Both are repaired and
verified. The remaining results describe test fixtures, public metadata,
intentional typing or control flow, and optional configuration/style advice.
No query exclusions or new GitHub dismissals were added.

## Repairs

### vpn-confinement diagnostic descriptors

`modules/vpn-confinement/doctor.py` could leak an open descriptor when a
resolver path was a directory. `os.fdopen` raised before its context manager
acquired ownership. Both `read_text` and the confined `read_rooted` path
reproduced the leak.

The opener now closes each descriptor in `finally`. The shared `read_fd`
helper explicitly borrows it and wraps it with `closefd=False`. This also
closes descriptors when wrapping, decoding, reading, or cancellation fails.
Regular-file checks, bounded reads, nonblocking FIFO handling, and openat2's
process-root confinement remain intact. Read failures still return `None`.

The regression in `tests/eval/test_doctor.py` exercises directories, FIFOs,
invalid UTF-8, and oversized files through both entry points. It fails twice
against the original code, once for each directory-reading path, and passes
after the fix. The existing successful reads and confinement tests also pass.
All 14 doctor tests pass directly and in the Nix `diagnostics` check. The final
Python CodeQL scan returns zero results.

### Hyprland regression-runner lock

`tests/hyprland/run-upstream-local.py` opened its serialization lock without
explicitly closing it. A context manager now holds the lock through setup,
execution, process termination, and evidence collection, then closes it on
success or failure. Comments explain why cleanup ignores already-exited
process groups. The diagnostic helper's intentional failed-inspection catch
also has an explanatory comment.

Four isolated tests verify lock closure after normal protocol completion,
setup failure, process-start failure, and cleanup failure. They also verify
that cleanup runs while the lock is still held. They do not start a compositor.
The final CodeQL scan no longer reports the lock or its empty exception blocks.

## Coverage

Scans use CodeQL CLI 2.26.4 and GitHub's `security-and-quality` suites, which
include security queries plus reliability and maintainability checks.
See [GitHub's query-suite documentation](https://codeql.github.com/codeql-query-help/).

Each repository was copied from its current tracked and nonignored untracked
files, including staged and unstaged work. Submodules were scanned separately.
Snapshots, file hashes, original diffs, command lines, logs, and SARIF output
are retained in
`~/.cache/nix-forge-codeql/20260907`.

| Repository | Local scans | Open GitHub CodeQL alerts | Remaining local results |
| --- | --- | ---: | ---: |
| nix-conf | Actions, Python, Rust, compiled C/C++ | 0 | 13 |
| nixpkgs-personal | Actions, Python, C/C++ without a build | 0 | 29 |
| nix-seal | Actions, Python, Rust | 0 | 22 |
| nix-config-framework | Actions | 0 | 1 |
| vpn-confinement | Actions, Python, JavaScript/TypeScript | 0 | 1 |

The final 14 scans have 66 remaining results, assessed below. Those are raw
scanner results, not 66 confirmed vulnerabilities.

The installed CodeQL 2.26.3 package initially could not launch its generic
Linux Rust and C++ extractors on NixOS. An isolated compatible Linux environment
with CLI 2.26.4 resolved that failure and the initial Python parser failures.
Rust extraction also required the actual compiler, Cargo, and Rust library
sources. Earlier scans without this setup omitted macro expansion and were
not accepted as the final Rust result. Final nix-seal extraction has no warning
diagnostics and reproduces its 21 known alerts. The smaller nix-conf Rust scan
has one type-information diagnostic and no results.

The nix-conf C/C++ scan compiles both native test programs with their Qt,
Pango, Wayland, and generated protocol dependencies. It has no extraction
warnings. The nixpkgs-personal C/C++ scan uses CodeQL's no-build mode; its macOS
bridge was not compiled natively.

All 23 local Swift files in nixpkgs-personal match GitHub commit
`b9719a81aa8d88b4a3d22b2b9014acd3e3cac344` byte-for-byte. That commit's successful
Swift analysis, ID `1738121354`, reports zero results. This is matching remote
evidence, not a local Swift execution. The standalone nix-conf Core Text test
has no equivalent Swift scan. Native macOS checks were skipped at the user's
request because the MacBook was unavailable.

CodeQL does not directly analyze Nix or shell source. Embedded programs and
third-party source contained only in patch files are not equivalent to
extracted compilation units. This review does not claim coverage of those
languages or an exhaustive security audit. GitHub Scorecard alerts are a
different tool and were not treated as CodeQL findings.

## Remaining local results

| Rule or pattern | Count | Assessment |
| --- | ---: | --- |
| Rust cleartext logging | 21 | Public object IDs, ciphertext metadata, schemas, public recipients, and counts; individual alerts listed below. |
| Python cleartext storage | 1 | Hardcoded password fixtures in private temporary test directories. |
| Python mixed returns | 26 | Every reported unsuccessful path calls `_fail`, which is annotated `NoReturn` and unconditionally raises `SystemExit(1)`. No implicit `None` return exists. |
| Python ineffectual statements | 4 | Ellipsis bodies of valid `@overload` declarations. |
| Python unused `Iterable` import | 1 | Used in a string type argument to `cast`; the `TYPE_CHECKING` import supports type checking. |
| Python implicit string concatenation | 1 | Intentionally creates one Python program for the single `-c` argument in the OOM test. |
| Python mixed import styles | 2 | Both `unittest` and its imported mock helpers are used. Optional style advice. |
| C/C++ multiplication before widening | 4 | Private test helper has only the fixed dimensions 200, 100, and 50; all byte counts fit in `int`. |
| C/C++ path injection and file mode | 2 | The mock CEF library reads its log path from the Nix test environment, inside the build directory. The mock is never installed; the production library does not use this path. |
| Actions advanced-configuration suggestion | 4 | Explicit repository workflows retain reviewed triggers and required checks. Switching setup mode is optional, not a security repair. |

The initial unused-listener warnings disappeared when C/C++ headers were
generated and the code was compiled. The initial unused TLS-context warning
disappeared when the importing Python file was successfully extracted. No
correct source was removed to silence these tooling artifacts.

## Dismissed GitHub alerts

The full alert lists and every CodeQL alert's instance history were retrieved
with pagination. Each alert has a separate `triage-finding/v0` record in the
artifact directory. Each current-source verdict is `not_actionable`, with
high confidence. No GitHub alert state was changed.

| Repository and alert | Source evidence |
| --- | --- |
| nix-conf #8 | `write_secret` has only test callers supplying hardcoded dummy credentials. |
| nix-seal #29 | `run_doctor` prints public plan/cache counts and hashes. |
| nix-seal #30 | `run_schema` serializes a generated JSON Schema, not an instance. |
| nix-seal #31 | `run_template_check` prints a public template count. |
| nix-seal #32 | Manifest verification prints public IDs, generation, and signer count. |
| nix-seal #33 | `run_rekey` prints a ciphertext cache identifier. |
| nix-seal #34 | Provision dry-run prints public policy IDs and delivery mode. |
| nix-seal #35 | Provision results print public IDs, delivery, and ciphertext cache keys. |
| nix-seal #36 | Generation status uses declared output IDs and ciphertext paths. |
| nix-seal #37 | Lifecycle reports contain public IDs and lifecycle state. |
| nix-seal #38 | `arguments.secret` is a validated public `Id` selector. |
| nix-seal #39 | `Secret.source` is a canonical ciphertext path in public policy. |
| nix-seal #40 | Collection entries print public mapping IDs and ciphertext paths. |
| nix-seal #41 | Rekey dry-run prints public ID and recipient count before loading an identity. |
| nix-seal #42 | Recipient output comes from `Identity.public`, not private keys. |
| nix-seal #43 | Artifact status contains public IDs, delivery, and ciphertext path. |
| nix-seal #44 | Activation prints artifact/template counts and changed status. |
| nix-seal #45 | Deletion status prints a public ID after quarantining ciphertext. |
| nix-seal #46 | Authoring prints a public ID; plaintext is passed separately to encryption. |
| nix-seal #47 | Batch status prints `results.len()`, not batch plaintext. |
| nix-seal #48 | Rekey completion prints the public policy selector. |
| nix-seal #49 | Edit completion prints the public selector, not edited contents. |

## Verification and handoff

Successful focused checks:

```sh
python3 ~/Developer/vpn-confinement/tests/eval/test_doctor.py
nix build ~/Developer/vpn-confinement#checks.x86_64-linux.diagnostics --no-link
python3 ~/.cache/nix-forge-codeql/20260907/test_runner_lock.py
```

Changed Python files compile. Independent review found no concrete bypass or
regression. The final descriptor ownership adjustment was also checked through
both callers and rescanned, producing zero Python results in vpn-confinement.
`canonical-scans.json` selects the final SARIF files;
`local-results.json` preserves all 66 residual results with locations.
`*-triage.json` preserves the 22 individual GitHub assessments.

The SSH configuration requested during this review is documented in
[SSH from desktop to MacBook](desktop-macbook-ssh.md). It has been evaluated
and syntax-checked, but neither machine has been activated. The broader
desktop contract's unchanged Finder Favorites assertion currently fails.
No commits, pushes, GitHub dismissals, or system deployments were performed.
