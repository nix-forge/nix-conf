# CI efficiency audit

Reviewed: 2026-09-14. Scope: every repository in the `nix-forge` GitHub
organization and the current `nix-conf` check graph. Local analysis used the
working trees and revisions present on the review date. Timing analysis used the
GitHub Actions API and completed runs available on that date.

## Answer

`nix-conf` spends almost all of its CI time in one three-platform native job.
The cheap jobs are not the problem. In the last five successful CI runs, the
repository hooks averaged 2.7 minutes, while successful native cells averaged
50.0 minutes on x86 Linux, 53.3 minutes on ARM Linux, and 19.5 minutes on
Darwin. The package repository has the other large workload: its native build
cells averaged 86.8, 71.5, and 48.9 minutes respectively.

The worst `nix-conf` repetition was concrete. The `generated-artifacts` check is
a link-farm convenience target over checks exposed elsewhere by name. CI built
the named checks and then evaluated the aggregate on every system. In
[run 34737000550](https://github.com/nix-forge/nix-conf/actions/runs/34737000550),
that aggregate accounted for 30.8 minutes of the x86 check step and 37.4 minutes
of the ARM check step. Five more policy checks each inspect every supported
target internally, but CI repeated them in all three matrix cells.

The implemented partition keeps the full ordinary `checks` output intact for
local `nix flake check`. Hosted CI now:

* omits `generated-artifacts`, because its member checks retain direct CI owners;
* runs `cache-policy`, `git-email-privacy`, `platform-contracts`,
  `secret-templates`, and `temporary-package-fixes` once on x86 Linux;
* moves the Gitleaks policy canary into the existing x86 lint partition;
* leaves desktop workstation assurance checks out of generic hosted CI;
* uses shared CI v2.5.4 in the four repositories that were still on v2.5.0;
* makes the root native-package matrix an explicit manual audit instead of a
  routine pull-request and merge-queue requirement.

The final pull-request run measured the result rather than projecting it. The
entire workflow completed in about 29 minutes. All six x86 check shards finished
in under 20 minutes; their slowest wall time was about 16.5 minutes, down from a
50-minute historical average for the monolithic x86 native cell. The remaining
x86 critical path was a real native-package shard at about 26.5 minutes. The
slowest of four ARM check shards finished in about 24.9 minutes and Darwin in
about 27.2 minutes.

A later broad package update exposed a modulo bucket with four expensive
packages that ran for more than 60 minutes. The root flake re-exports package
outputs whose source repositories already require native builds, while the
root's required checks own its generated documentation and integration
contracts. Routine root CI now evaluates those exports but leaves repeated
native builds to their source repositories. A manual dispatch can still set
`build_native_packages` for an explicit root-lock-context audit.

A later live run exposed a stronger x86-specific problem. Before reaching the
encrypted-storage test, `desktop-authentication`, `desktop-commands`, and
`desktop-memory-policy` consumed 37.5, 36.6, and 32.0 minutes respectively on a
GitHub runner. `desktop-storage-install` then remained active for more than an
hour while building and booting the full disposable encrypted-disk VM. These
checks consume workstation artifacts or exercise workstation VM behavior; they
are now excluded from `ciChecks` along with the desktop I/O-cost VM, generated
storage assurance, and the full Zen browser wrapper build. They remain in
`checks.x86_64-linux` for explicit local or desktop-host validation. The full
Sentry crashpad-lock build and `public-demo-runtime` VM are excluded for the
same reason, while their lightweight contracts retain hosted owners. The
portable Python suite runs on x86 and is no longer repeated on ARM; Darwin keeps
its platform-specific Python coverage.

## Organization workflow inventory

GitHub reported eight organization repositories. The workflow column lists
repository-owned workflow files on the default branch. Dynamic Dependabot and
Copilot workflows are excluded from the count because they are not stored in
the repository.

| Repository | Stored workflows | Main CI jobs | Slowest successful job in the five-run sample |
| --- | ---: | --- | ---: |
| `.github` | 2 | validation, queue callback | validation, 0.5 min average |
| `ci` | 8 | validation, CodeQL, queue callback | CodeQL, 1.0 min average |
| `nix-conf` | 7 active, 2 disabled | discovery, lock checks, removed-symbol check, hooks, six x86 check shards, four ARM check shards, Darwin, aggregate status, queue callback; native-package builds are manual opt-in | Required x86 check shards are below 20 min; root native builds duplicated source-repository ownership and produced a 60+ min hot bucket |
| `nix-config-framework` | 8 | discovery, lock checks, hooks, three native cells, queue callback | Darwin native checks, 2.9 min average |
| `nix-homelab` | 7 | discovery, lock checks, format, lint, two Linux cells, queue callback | x86 checks, 5.4 min after routine VM exclusions; ARM, 4.8 min |
| `nix-seal` | 9 | Rust on two hosts, MSRV, three Nix cells, tooling, vet, audit, fuzz, benchmarks, policy, queue callback | x86 Nix, 9.4 min average |
| `nixpkgs-personal` | 9 | discovery, lock checks, lint, evaluation, three builds, Swift quality and sanitizer jobs, NUR, queue callback | x86 build, 86.8 min average |
| `vpn-confinement` | 7 | discovery, lock checks, format, lint, two Linux cells, queue callback | x86 checks, 7.7 min average |

The five-run sample is deliberately small and recent. Cancelled jobs were not
included in the job averages. It describes observed duration, not billed time,
cache transfer, or queue delay. The root sample contained only two successful
instances of each native matrix cell because some otherwise successful workflow
runs skipped draft-only work.

The organization already has several sound controls. Required CI workflows use
broad pull-request or merge-queue triggers. Long jobs have timeouts. Workflow
concurrency cancels superseded pull-request runs. GitHub documents that a
concurrency group permits one running member and that `cancel-in-progress`
cancels the current member when configured. Including the workflow name avoids
cross-workflow cancellation. See the
[GitHub concurrency reference](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).

The audit found no case where merging small jobs would materially shorten the
critical path. Lock health, queue callbacks, review requests, dependency review,
and most security workflows finish in seconds or a few minutes. Removing them
would save little and would discard distinct failure signals.

## `nix-conf` check inventory

The current flake exposes 77 checks on x86 Linux, 64 on ARM Linux, and 45 on
ARM Darwin. After this change, the hosted partitions contain 53, 46, and 32
native checks. The x86 lint partition contains eight checks. Ordinary
`nix flake check` still sees every check.

| Owner | Checks and purpose | Hosted treatment |
| --- | --- | --- |
| `flake/lint-checks.nix` | `documentation`, `gitleaks-policy`, `javascript-quality`, `pre-commit`, `python-quality`, `stylesheet-quality`, `swift-quality`, `treefmt` | One x86 lint job. This avoids repeating portable tooling in native jobs. |
| `flake/dev/configurations.nix` | `nixos-configuration-desktop`, `darwin-configuration-macbook-pro-m4` | Evaluates the native closure path without building a host closure. Retained. |
| `flake/dev/generated-config-checks.nix` | Bash, Nushell, PowerShell, Lua, JSON, OpenSSL, Caddy, desktop command, and application config checks; `generated-artifacts` aggregate | Named checks retained. Aggregate removed from hosted CI. |
| `flake/dev/noogle-checks.nix` | Browser openers, Gecko policy merge, GTK parser, fonts, Linearmouse, service arguments, wallpaper ordering, and related generated behavior | Retained by name, so removing the aggregate loses no coverage. |
| `flake/dev/checks.nix` | Secret templates, Python and stylesheet quality, Gitleaks canaries, ClamAV runtime checks, macOS dry-run behavior | Secret templates run once in hosted CI. Gitleaks joins lint. Full ClamAV VM runtime remains explicit local assurance; smaller contracts remain hosted. |
| `flake/dev/python-checks.nix` | Root Python behavior suite | Runs once on x86 Linux instead of being repeated on ARM; Darwin retains platform-specific behavior. |
| `flake/dev/fonts.nix` | Selection, Linux browser rendering, Linux native rendering | Retained on their native platforms. The separate Darwin Core Text command consumes `font-selection`. |
| `flake/dev/cache-checks.nix` | Nix cache policy across NixOS, Home Manager, Darwin, and the real hosts | Runs once because one derivation already evaluates all targets. |
| `flake/dev/platform-checks.nix` | Package availability and shared module behavior across all three systems | Runs once because it imports and asserts all three systems itself. |
| `flake/dev/git-privacy-checks.nix` | Git identity and privacy policy for both configured homes | Runs once because one derivation evaluates both homes. |
| `flake/dev/temporary-fix-checks.nix` | Temporary override guards across all systems; native crashpad, VS Code, and Swift checks | The cross-system guard runs once. Native checks stay on their supported systems. |
| `flake/dev/local-control-checks.nix` | Darwin local-control database, TLS, environment, preparation, activation, Swift, and Rust behavior | Retained on Darwin, with the portable TLS contract also present on Linux. |
| `flake/dev/authentication-checks.nix`, `memory-checks.nix`, `storage-checks.nix`, `virtualisation-checks.nix` | Desktop authentication, memory, storage, and virtualization behavior | Workstation-coupled builds and VMs stay available as explicit desktop/local assurance; lightweight virtualization artifact checks remain hosted. |
| `flake/dev/theme-checks.nix` | Theme target discovery and Noctalia palette behavior | Retained across systems. |
| `flake/public-guide.nix` | Public guide recipes and demo runtime | Recipes and consumer contracts remain hosted. The graphical demo VM is explicit local assurance. |
| `flake/deploy.nix` | `deploy-schema`, `deploy-activate`, and `zen-wrapper-copy-regression` | Remain explicit local/desktop assurance because they build the desktop closure or full wrapped browser. |

The inventories are computed rather than copied into workflow YAML. Tests in
`tests/ci/test_ci_inventory.py` verify that a new ordinary check enters CI while
deployment, lint, aggregate, and once-per-revision exclusions keep their stated
owners.

## Why v2.5.4 matters

The repositories used immutable pins, but four main workflows still selected
shared CI v2.5.0. The v2.5.4 runner includes the unchanged-derivation selection
introduced in
[v2.5.3](https://github.com/nix-forge/ci/blob/a53126de1b983ccdb5ab7b1ab9989ef921a880d5/scripts/run-flake-checks.py),
which compares each current check derivation with the PR or merge-queue base and skips
the build when the derivation path is unchanged. The base lookup is conservative:
an unavailable or invalid base causes a rebuild rather than a silent omission.
This directly helps root, framework, seal, and package pull requests whose edits
do not affect every check.

This mechanism does not eliminate evaluation cost. It evaluates current and
base derivations separately. That is why removing the expensive aggregate and
cross-system repetitions still matters.

## Best-practice decisions

Do not add workflow-level `paths` filters to required CI. GitHub documents that
a workflow skipped by branch or path filtering leaves its required check
pending, which can block merging. See
[workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
and [required-check troubleshooting](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks).

Keep `fail-fast: false` on the native matrices. The organization uses the matrix
to collect platform evidence, and GitHub documents that fail-fast cancels other
cells after a non-tolerated failure. Faster failure would hide the second and
third platform results. The same
[workflow syntax reference](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
defines matrix and timeout behavior.

Keep evaluation and build claims separate. Nix documents that `nix flake check`
builds checks by default, while `--no-build` only validates flake outputs. See
the [Nix flake-check reference](https://nix.dev/manual/nix/2.24/command-ref/new-cli/nix3-flake-check).
The repositories correctly retain native builds where runtime or package
materialization matters.

Do not enable a GitHub-hosted Nix store cache without a benchmark. GitHub cache
entries use exact and prefix matching, save new entries only after successful
jobs, and must not contain sensitive data. See the
[GitHub dependency-cache reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).
The shared setup action bounds its optional Nix cache at 2 GiB, but the framework
benchmark has not yet established a benefit for these larger repositories. The
existing external substituters remain useful when they contain the requested
paths. Nix requires configured substituters and trusted signing keys, as described
in the [Nix binary-cache guide](https://nix.dev/guides/recipes/add-binary-cache.html).

## Validation and limits

The CI inventory suite passed all 33 tests on x86 Linux. All three `ciChecks`
outputs and the x86 `lintChecks` output evaluated after the partition change.
Repository hooks passed YAML parsing, Pinact, Zizmor, formatting, Gitleaks, and
the other checks relevant to these files. The complete pull-request workflow
then passed every required check. No host was activated or deployed, and Darwin
runtime behavior was validated by hosted CI rather than locally.

Package build time remains workload-driven. The package repositories retain
native changed-output coverage, and root native builds remain available as a
manual audit. Routine root CI does not repeat that work. The other removals
target duplicate aggregates, cross-platform repetition, workstation-only VMs,
and full-system tests without suitable hosted-runner fidelity.
