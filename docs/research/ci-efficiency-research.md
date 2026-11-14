# CI efficiency audit

Reviewed: 2026-09-14. Scope: every repository in the `nix-forge` GitHub
organization and the current `nix-conf` check graph. Local analysis used the
working trees and revisions present on the review date. Timing analysis used the
GitHub Actions API and completed runs available on that date.

The [2026-11-09 follow-up](#development-follow-up) distinguishes the current
publication blocker from the historical timing sample below.

## Answer

Before this change, `nix-conf` spent almost all of its CI time in one
three-platform native job.
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
* uses shared CI v2.5.4;
* distributes checks with six x86 Linux shards, four ARM Linux shards, and one
  Darwin shard using deterministic duration weights;
* runs public-guide consumer validation in its own three-runner matrix;
* gives each Linux runner four build cores and the Darwin runner three, while
  keeping one Nix build job per runner;
* moves changed native-package materialization to an explicit manual audit with
  four x86 Linux, two ARM Linux, and one Darwin shard;
* keeps the GitHub-hosted Nix cache disabled in ordinary CI and exposes it only
  as a manual benchmark. The package audit never uses that cache.

The current inventory gives the weighted allocator estimated loads of 17, 17,
16, 17, 16, and 16 on x86 Linux, and 20 on each ARM Linux shard. These are
relative scheduling estimates, not post-change runtime measurements. Darwin
remains one native runner because its checks are platform-specific and the
hosted architecture cannot be subdivided across machines by this workflow.
Changed package builds and checkout/setup time remain.

A later live run exposed a stronger x86-specific problem. Before reaching the
encrypted-storage test, `desktop-authentication`, `desktop-commands`, and
`desktop-memory-policy` consumed 37.5, 36.6, and 32.0 minutes respectively on a
GitHub runner. `desktop-storage-install` then remained active for more than an
hour while building and booting the full disposable encrypted-disk VM. These
checks consume workstation artifacts or exercise workstation VM behavior; they
are now excluded from `ciChecks` along with the desktop I/O-cost VM, generated
storage assurance, and the full Zen browser wrapper build. They remain in
`checks.x86_64-linux` for explicit local or desktop-host validation.

## Organization workflow inventory

GitHub reported eight organization repositories. The workflow column lists
repository-owned workflow files on the default branch. Dynamic Dependabot and
Copilot workflows are excluded from the count because they are not stored in
the repository.

| Repository | Stored workflows | Main CI jobs | Slowest successful job in the five-run sample |
| --- | ---: | --- | ---: |
| `.github` | 2 | validation, queue callback | validation, 0.5 min average |
| `ci` | 8 | validation, CodeQL, queue callback | CodeQL, 1.0 min average |
| `nix-conf` | 7 active, 2 disabled | discovery, lock checks, removed-symbol check, hooks, sharded native checks, public-guide checks, optional package audit, aggregate status, queue callback | ARM native checks, 53.3 min average |
| `nix-config-framework` | 8 | discovery, lock checks, hooks, three native cells, queue callback | Darwin native checks, 2.9 min average |
| `nix-homelab` | 7 | discovery, lock checks, format, lint, two Linux cells, queue callback | x86 checks, 17.4 min average and 49.3 min maximum |
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
ARM Darwin. After this change, the hosted partitions contain 53, 45, and 30
native checks. The x86 lint partition contains eight checks. Ordinary
`nix flake check` still sees every check.

| Owner | Checks and purpose | Hosted treatment |
| --- | --- | --- |
| `flake/lint-checks.nix` | `documentation`, `gitleaks-policy`, `javascript-quality`, `pre-commit`, `python-quality`, `stylesheet-quality`, `swift-quality`, `treefmt` | One x86 lint job. This avoids repeating portable tooling in native jobs. |
| `flake/dev/configurations.nix` | `nixos-configuration-desktop`, `darwin-configuration-macbook-pro-m4` | Evaluates the native closure path without building a host closure. Retained. |
| `flake/dev/generated-config-checks.nix` | Bash, Nushell, PowerShell, Lua, JSON, OpenSSL, Caddy, desktop command, and application config checks; `generated-artifacts` aggregate | Named checks retained. Aggregate removed from hosted CI. |
| `flake/dev/noogle-checks.nix` | Browser openers, Gecko policy merge, GTK parser, fonts, Linearmouse, service arguments, wallpaper ordering, and related generated behavior | Retained by name, so removing the aggregate loses no coverage. |
| `flake/dev/checks.nix` | Secret templates, Python and stylesheet quality, Gitleaks canaries, ClamAV runtime checks, macOS dry-run behavior | Secret templates run once in hosted CI. Gitleaks joins lint. Native runtime checks remain platform-scoped. |
| `flake/dev/python-checks.nix` | Root Python behavior suite | Retained on x86 Linux and Darwin; the platform-independent suite is removed from the duplicate ARM Linux shard. |
| `flake/dev/fonts.nix` | Selection, Linux browser rendering, Linux native rendering | Retained on their native platforms. The separate Darwin Core Text command consumes `font-selection`. |
| `flake/dev/cache-checks.nix` | Nix cache policy across NixOS, Home Manager, Darwin, and the real hosts | Runs once because one derivation already evaluates all targets. |
| `flake/dev/platform-checks.nix` | Package availability and shared module behavior across all three systems | Runs once because it imports and asserts all three systems itself. |
| `flake/dev/git-privacy-checks.nix` | Git identity and privacy policy for both configured homes | Runs once because one derivation evaluates both homes. |
| `flake/dev/temporary-fix-checks.nix` | Temporary override guards across all systems; native crashpad, VS Code, and Swift checks | The cross-system guard runs once. Native checks stay on their supported systems. |
| `flake/dev/authentication-checks.nix`, `memory-checks.nix`, `storage-checks.nix`, `virtualisation-checks.nix` | Desktop authentication, memory, storage, and virtualization behavior | Workstation-coupled builds and VMs stay available as explicit desktop/local assurance; lightweight virtualization artifact checks remain hosted. |
| `flake/dev/theme-checks.nix` | Theme target discovery and Noctalia palette behavior | Retained across systems. |
| `flake/public-guide.nix` | Public guide recipes and demo runtime | Consumer validation runs in its own three-system matrix; the large demo runtime remains outside generic hosted `ciChecks`. |
| `flake/deploy.nix` | `deploy-schema`, `deploy-activate`, and `zen-wrapper-copy-regression` | Remain explicit local/desktop assurance because they build the desktop closure or full wrapped browser. |

The inventories are computed rather than copied into workflow YAML. Tests in
`tests/ci/test_ci_inventory.py` verify that a new ordinary check enters CI while
deployment, lint, aggregate, and once-per-revision exclusions keep their stated
owners.

## Why v2.5.4 matters

The repositories use immutable pins, and this workflow now selects shared CI
v2.5.4. The
[v2.5.4 runner](https://github.com/nix-forge/ci/blob/b5ec655589b52df24c9b38d20a6b4bf364ec35cc/scripts/run-flake-checks.py)
compares each current check derivation with the PR or merge-queue base and skips
the build when the derivation path is unchanged. The base lookup is conservative:
an unavailable or invalid base causes a rebuild rather than a silent omission.
The repository-owned runner now adds weighted partitioning on top of that
derivation comparison.

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

Normal CI leaves the GitHub-hosted Nix store cache disabled. A
`workflow_dispatch` can opt into one bounded benchmark through
`use_nix_cache`; the check and guide jobs share one cache scope per platform,
while the native package audit always keeps caching off. GitHub cache entries
use exact and prefix matching, save new entries only after successful jobs, and
must not contain sensitive data. See the
[GitHub dependency-cache reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).
The pinned [shared setup action](https://github.com/nix-forge/ci/blob/b5ec655589b52df24c9b38d20a6b4bf364ec35cc/actions/setup-nix/action.yml)
bounds its optional Nix store at 2 GiB. That limits the size of each runner's
cache candidate, but repository-level cache eviction and transfer time still
need to be measured. The existing external substituters remain useful when
they contain the requested paths. Nix requires configured substituters and
trusted signing keys, as described in the
[Nix binary-cache guide](https://nix.dev/guides/recipes/add-binary-cache.html).

## Validation and limits

The CI inventory tests passed on x86 Linux. All three `ciChecks` outputs and the
x86 `lintChecks` output evaluated after the partition change. The 445-test
Python behavior derivation passed, and the repository hooks passed actionlint,
Pinact, YAML/tree formatting, and the focused Ruff checks for the new runner.
The broader Python quality derivation still reports one pre-existing unresolved
import in `nix-homelab/scripts/downloaders/qbittorrent_config.py`. No host was
built, activated, or deployed. Darwin runtime behavior was not run locally.

The scheduling estimates need one completed pull-request or merge-queue run
before they become measured evidence. Package build time remains workload-driven;
v2.5.4 skips unchanged checks, but a genuinely changed large package can still
consume most of a native build cell.

## Development follow-up

Reviewed: 2026-11-09 PST. Current-source observations include uncommitted root
and package-submodule work; they are not claims that those bytes are deployed.
GitHub run metadata is separate evidence about the published candidate.

### Current blocker and evidence boundary

At 2026-11-10 04:39 UTC, [package PR 212](https://github.com/nix-forge/nixpkgs-personal/pull/212)
was open and six native build jobs in [run 42728215078](https://github.com/nix-forge/nixpkgs-personal/actions/runs/42728215078)
were still in progress. Each had completed its declared native CI-check step
and was running the affected-package build step. This identifies the phase
holding up downstream publication. It does not prove a stall, OOM, failed
substitution, or a particular expensive dependency; those need package logs or
terminal reports. Cancelling a healthy build would discard progress.

The existing source already selects affected derivations, preserves conservative
base-history fallback and partitions native work. Recommending those features as
new work would duplicate completed engineering. The remaining evaluator opportunity
is process reuse: the package working-tree runner evaluates base derivations as
a map but obtains current derivations per package. Shared CI also evaluates
current/base check derivations separately per check.
[Package runner](../../pkgs/.github/scripts/build-affected.sh),
[pinned shared runner](https://github.com/nix-forge/ci/blob/1a6dfe0b851c69ad30169977e014bd45029e9c55/scripts/run-flake-checks.py).

### Implementation-ready next steps

1. Keep queued local acceptance bound to an immutable root/submodule manifest.
   Archive the intended source, retain required roots and validate exact source
   identity before executing checks. Include intended dirty changes explicitly;
   archiving commits alone must not silently omit them. This avoids source
   churn invalidating an expensive wait.
   [Nix flake archive](https://nix.dev/manual/nix/2.35/command-ref/new-cli/nix3-flake-archive.html).
2. In the package repository, evaluate the current package derivation map once,
   mirroring its existing base map. Preserve exact package selection, licensing
   exclusions, failed/missing-base fallback and native check ownership. Test
   invocation count, identical selected derivations, empty selection and malformed
   evaluation output before measuring elapsed time. A bulk evaluation failure
   must remain explicit; it cannot turn omitted entries into unchanged packages.
3. Propose the analogous change separately in the shared CI repository. Retain
   per-check failure reporting and bounded evaluation; one expression forced
   across every check can fail as a whole or require more peak memory. A smaller
   bounded batch may be preferable. Measure process count, evaluation duration
   and peak memory rather than assuming a single giant map is faster.
4. Use existing comparable reports to identify expensive repeated dependency
   builds before changing caches. Root cache benchmarking is opt-in; package
   native CI remains cache-disabled. Any future pilot needs an agreed compute
   budget, trusted writes, exact platform/lock identity, licensing review and
   restore/save overhead measurements. Do not upload private or excluded outputs.
   Nix signed substitution and GitHub dependency caches have different trust
   boundaries; neither proves a required native runtime test passed.
   [Nix cache trust](https://nix.dev/guides/recipes/add-binary-cache.html),
   [GitHub cache security](https://docs.github.com/en/actions/concepts/workflows-and-actions/dependency-caching).
5. Preserve required check names and merge-group coverage. Use internal affected
   selection rather than skipping an entire required workflow by path. Changing
   a workflow trigger can leave a required check pending and block merges.
   [Required-check troubleshooting](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks).

The root owns integration and the source manifest; the package repository owns
its affected-package runner; shared CI owns common evaluation behavior. Keep
those changes in their owning repositories and update gitlinks only after the
matching revision passes. Do not copy shared runner code into this repository.

### Validation and limits

This follow-up read source, primary documentation and GitHub metadata. It started
no hosted run, local build, cache benchmark, deployment or merge. It does not
claim that any proposed batching/cache change has saved time. The
[queue follow-up](build-queue-efficiency-research.md#development-efficiency-follow-up)
records local admission, deadline and preflight improvements.
