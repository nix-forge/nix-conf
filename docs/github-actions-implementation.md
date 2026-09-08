# Shared CI and NUR implementation

Implemented 2026-09-07, America/Los_Angeles. The design follows
[the research](github-actions-strategy-research.md): own the organization policy
and reuse maintained upstream actions for installation, scanning and caching.

## Published shared repositories

- [nix-forge/ci](https://github.com/nix-forge/ci) contains reusable lockfile, CodeQL,
  dependency-review, reviewer-request, Dependabot auto-merge and NUR workflows.
  Small composite actions provide Nix setup, queue reconciliation and queue
  completion callbacks. Platform builds remain in each consumer repository.
- [nix-forge/.github](https://github.com/nix-forge/.github) provides organization
  workflow templates and the public profile. CI validates the templates.
- Consumers pin `a75d21dababfd55145e2df1db81f3d2d865bec59`, the source of
  [immutable release v1.0.1](https://github.com/nix-forge/ci/releases/tag/v1.0.1).
  The initial v1.0.0 points to the same source; consumer comments retain that
  version label. Dependabot proposes later pin updates.

Both new repositories require pull requests and their successful `validate` check
on main, including for administrators. They prohibit force pushes and branch
deletion, require linear history, enforce action SHA pinning and default to a
read-only workflow token. Repository settings were verified through GitHub's API.

## Consumer rollout

The migrations remove a net 4,263 lines from the five consumer `.github` trees.
That count includes consolidating the queue implementation and regression tests;
it does not count new files in the shared repository as a reduction in total code.

| Repository | Migration |
| --- | --- |
| nix-config-framework | [PR #40](https://github.com/nix-forge/nix-config-framework/pull/40) |
| vpn-confinement | [PR #56](https://github.com/nix-forge/vpn-confinement/pull/56) |
| nixpkgs-personal | [PR #47](https://github.com/nix-forge/nixpkgs-personal/pull/47) |
| nix-seal | [PR #80](https://github.com/nix-forge/nix-seal/pull/80) |
| nix-conf | [PR #189](https://github.com/nix-forge/nix-conf/pull/189) |

Required-check names are migrated only after observing the replacement checks
succeed on the actual PR revision. Existing check coverage and GitHub Actions app
identity are preserved. The package repository will also gain required locked and
unstable NUR checks after its earlier package PR has cleared the queue. Required
check names are not changed while an older workflow definition is still queued. Merges use the existing native merge queue and its checks.
No administrator bypass is used.

Native Linux and macOS coverage, Swift's manual CodeQL build, Rust assurance and
release checks, documentation deployment and Scorecard publication retain their
repository-specific definitions. No hosted workflow builds the nix-conf desktop
system closure. Dependabot minor/patch groups now use the actual `update-types`
field. New templates, named jobs and NUR evaluation summaries improve onboarding
and failed-run diagnosis.

## Security and automation behavior

- Shared actions and their third-party dependencies use full commit SHAs.
- Privileged queue reconciliation executes the pinned shared action's script
  without checking out caller code. Existing commit, run-attempt and job-result
  checks are retained.
- Automated admission refuses PRs changing workflow, local action or automation
  script files. Those changes need deliberate maintainer admission.
- Reusable workflows request explicit permissions and do not inherit all secrets.
  PR build jobs receive no new privileged credential.
- The existing GITHUB_TOKEN queue fallback remains. Moving admission to a GitHub
  App needs an installed App and a private key, followed by proof that its
  admission triggers native merge-group checks. No App credential is configured
  by this change. Scheduled reconciliation remains at the existing frequency to
  keep fallback validation from timing out.
- GitHub enforces full action SHA pins on all five consumers; VPN confinement's
  previously disabled setting was enabled after checking its pins.
- External binary-cache publication remains unconfigured. Unfree fonts and
  applications retain their package-specific redistribution controls.

## Cache experiment

The shared setup uses the pinned Determinate installer and optionally
`nix-community/cache-nix-action`. Store caching defaults to disabled. It saves only
on trusted default-branch pushes or dispatches. Keys include platform, Nix version,
job scope, lockfiles and commit; restoration does not cross lockfile identities.
Garbage collection targets 2 GiB before saving, but live roots can exceed that
size. The action does not request cache-purge permission.

The framework pilot ran the same Linux discovery check and evaluation at commit
`07e972f7e702603fda09860f4229961458c803ce`. Values below sum Nix setup, the workload
and Nix teardown, excluding runner provisioning and checkout.

| Run | Store cache disabled | Store cache enabled |
| --- | ---: | ---: |
| [Cold store](https://github.com/nix-forge/nix-config-framework/actions/runs/34174056740) | 23 s | 33 s |
| [Warm store](https://github.com/nix-forge/nix-config-framework/actions/runs/34174298367) | 22 s | 28 s |

The warm store restored approximately 160 MB successfully. It reduced the workload
from 13 to 6 seconds, but setup increased from 8 to 21 seconds. This small pilot
does not demonstrate an overall performance benefit, so `NIX_CI_CACHE=false` is
explicitly set on the framework repository. These two runs are not a statistical
benchmark of larger package builds. The manual benchmark remains available for
future measurements. The installer's own download cache is present in both cases.

## NUR preparation

The published package repository gains a root entry point accepting caller-provided
`pkgs`, a pinned NUR restricted evaluator, supported-platform metadata assertions,
locked/current-unstable CI and a weekly compatibility check. Its existing package
set passed 35 package/platform evaluations. User documentation covers direct-flake
and NUR usage, unfree opt-in, compatibility expectations and submission procedure.
Registration is prepared but has not been submitted upstream.

An existing [package PR #46](https://github.com/nix-forge/nixpkgs-personal/pull/46)
was already ahead of this migration in the merge queue. Its original check
requirements were restored while its native builds run. The combined migration is
prepared on
[`codex/shared-ci-after-fonts`](https://github.com/nix-forge/nixpkgs-personal/tree/codex/shared-ci-after-fonts).
It preserves that PR's font contracts, evaluation restrictions and cold-build
limits; adds provenance to its fonts; fixes Firefox Emoji's invalid Apache 2.0
Nixpkgs license identifier; and retains Noctalia's vendored MIT notice. Both NUR
inputs pass all 86 evaluations on this combined tree.

The package CI now compares base and current Nix derivation paths before rebuilding
selected packages. Identical recipes skip recompilation. Failed base evaluation or
missing history falls back to building. Explicit font and application contracts
remain active. Six fixture scenarios used real Nix evaluation and recorded build
commands to verify unchanged metadata, changed runtime, new package, missing base,
failed base evaluation and unchanged-package contract behavior. All passed. A
separate comparison found all 86 package/platform derivation paths unchanged by
the NUR metadata and notice fixes relative to PR #46's head. Evidence and the
reproducible fixture harness are saved under the migration `evidence` directory.

The expanded local package collection also receives source-provenance fixes for
precompiled fonts and its equivalent NUR integration. It passed all 86 supported
package/platform evaluations for both locked and current unstable Nixpkgs. The
restricted Linux index returned 13 entries for each. These local NUR checks did
not build the unpublished package additions.

See [NUR readiness](../pkgs/docs/nur-readiness.md) for exact results, metadata work
and the publication boundary. The local package additions and other pre-existing
work remain uncommitted. They were not included in the clean migration PRs.

## Validation and local placement

The shared library passed 25 queue regression tests, actionlint, pedantic Zizmor,
YAML lint and Ruff locally and in
[GitHub CI](https://github.com/nix-forge/ci/actions/runs/34173354615).
Each consumer passed its local workflow hooks; applicable native pre-push checks
also passed. GitHub runs the full existing native matrices on the PR and again in
the merge queue. NUR additionally runs its own restricted-evaluator matrix.

The new report passed its formatting and document checks in the original dirty
checkout. That checkout's hook also runs repository-wide Python lint and found
unrelated existing work in `tests/hyprland/run-upstream-local.py` and
`tests/systemd/check_chatgpt_oom.py`. Those files were not changed by this migration.
The clean nix-conf migration's repository-hooks job passed on GitHub.

Shared library checkout: `~/Developer/ci`.
Organization templates checkout: `~/Developer/nix-forge-community`.
Clean consumer checkouts, protection backups and cache timing JSON are under
`~/Developer/nix-forge-ci-migration`.

The clean checkouts avoid committing or overwriting existing work in
`~/Developer/nix-conf` and its dirty submodules. Incorporate the merged
remote CI changes when reconciling that work; its local branch and submodule
pointers have not been forcibly reset or advanced.
