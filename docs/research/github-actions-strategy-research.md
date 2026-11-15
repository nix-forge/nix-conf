# GitHub Actions strategy for nix-forge

Researched September 7, 2026. This is a recommendation, not an implementation.

Create `nix-forge/ci` to own reusable workflows and a small amount of organization-specific automation. Use established actions inside those workflows. Keep build definitions in each repository's Nix outputs and scripts. This gives nix-forge one place to maintain policy without taking responsibility for an installer, cache implementation, scanner, or CI service.

I would retain Determinate Nix during the migration, pilot an explicit Nix cache, and simplify the merge-queue authentication model separately. I would not build a general-purpose Marketplace action or move the organization to a different CI service now.

## Evidence from your repositories

I inspected all five public organization repositories through the GitHub API, including their workflows, dependency-update configuration, queue scripts and tests, active main-branch rules, and the latest 30 workflow runs per repository. The organization API reported the Free plan. Local files contain substantial concurrent changes and some older workflow implementations, so the comparisons below use these fixed remote revisions.

| Repository and inspected revision | Workflow files | YAML lines | Work that needs to remain repository-specific |
| --- | ---: | ---: | --- |
| [nix-conf](https://github.com/nix-forge/nix-conf/tree/a273575944bad657f575780f6a446bbc12f5fa7c/.github) | 7 | 456 | Submodules, font/browser checks, constrained evaluation, desktop and Darwin configuration coverage |
| [nix-config-framework](https://github.com/nix-forge/nix-config-framework/tree/73d6e973fd42ebf4c55dc7a59293eed391117109/.github) | 7 | 341 | Discovery checks and native platform coverage |
| [nixpkgs-personal](https://github.com/nix-forge/nixpkgs-personal/tree/6d4653b49f7ea3a3425d91af8fed9561b9b96e8f/.github) | 8 | 548 | Package selection, source updates, native package builds |
| [nix-seal](https://github.com/nix-forge/nix-seal/tree/0663f4d45bd93e621d11fa9e76f1376be9e585c5/.github) | 9 | 675 | Rust/MSRV, vetting, fuzzing, Miri, sanitizers, benchmarks, release provenance |
| [vpn-confinement](https://github.com/nix-forge/vpn-confinement/tree/7541b4da1ede65744743c1a15546c9ab20d47d85/.github) | 8 | 424 | Linux/NixOS checks and documentation publication |
| Total | 39 | 2,444 | |

These are inventory counts, not a claim that all 2,444 lines can be removed. The repeated families are flake-lock validation, Nix setup, hooks, CodeQL, dependency review, Scorecard, reviewer requests, auto-merge, and queue reconciliation. The existing use of full action SHAs, explicit permissions, disabled checkout credentials, native ARM runners, and separate assurance jobs is a useful foundation.

The strongest case for centralization is the queue implementation. Each repo carries a 374 to 379-line reconciler and 417 to 449 lines of tests. There are already three distinct script contents across the five copies. The reconciler admits selected bot PRs, dispatches missing queue validation, checks exact commits and run attempts, and mirrors successful jobs into commit statuses. [Inspected implementation](https://github.com/nix-forge/nix-conf/blob/a273575944bad657f575780f6a446bbc12f5fa7c/.github/scripts/reconcile-queue.py).

Each repo schedules reconciliation three times per hour. That is **360 scheduled opportunities per day** across five repos, before completion-triggered runs. GitHub may delay or skip scheduled execution, so this is configured frequency, not measured billing. In the latest 150-run sample, 76 entries were queue reconciliation, including skipped runs. One sampled completed reconciler job per repo took 5 to 6 seconds. This is primarily maintenance and Actions-tab noise, not evidence that reconciliation dominates compute cost. [Schedule](https://github.com/nix-forge/nix-conf/blob/a273575944bad657f575780f6a446bbc12f5fa7c/.github/workflows/reconcile-merge-queue.yml), [sample run](https://github.com/nix-forge/nix-conf/actions/runs/34165212702).

## Which approach fits

| Approach | Automation | Performance | Security and maintenance | UX/UI | Decision |
| --- | --- | --- | --- | --- | --- |
| Copy workflows or distribute templates alone | Easy onboarding; changes still need propagation | No inherent improvement | Copies drift | Familiar but inconsistent | Insufficient |
| One large custom action | Shares steps; callers still own jobs and events | No inherent improvement | You maintain execution code and runtime dependencies | Fewer obvious job boundaries | Wrong primary abstraction |
| Organization reusable workflows using existing actions | Shared jobs and policy; automated version updates | Central place to tune caching and scheduling | Small owned implementation; requires careful releases | Native job graph, logs and checks | Recommended |
| Adopt a generic Nix wrapper | Reduces Nix setup boilerplate | Depends on its cache and build choices | Inherits another project's defaults | Convenient for simple flakes | Does not cover the organization |
| Replace CI or the queue with a hosted service | Can remove substantial infrastructure work | Potentially useful build scheduling/cache | New service, permissions and operating model | Another dashboard | Revisit if measured constraints justify it |

Reusable workflows can define multiple jobs, runners, permissions, inputs, and outputs. Composite actions bundle steps inside a job. Your duplication crosses job and event boundaries, so reusable workflows fit better. Templates are useful for creating the short caller files, but generated copies do not acquire future template edits automatically. [GitHub's reuse comparison](https://docs.github.com/en/actions/concepts/workflows-and-actions/reusing-workflow-configurations).

Use `nix-forge/ci` for the versioned automation library. Add `nix-forge/.github` later if you want workflow templates presented in GitHub's new-workflow UI. Its templates should call `ci`, keeping implementation in one place. Neither repository currently appeared in the organization inventory. [GitHub template setup](https://docs.github.com/en/actions/how-tos/reuse-automations/create-workflow-templates).

## Actions and services to adopt or keep

| Component | Recommendation | Reason and boundary |
| --- | --- | --- |
| Nix installation | Keep `DeterminateSystems/determinate-nix-action` initially | Already used throughout current CI; avoids changing Nix distribution during extraction. Its build summaries and timelines suit your UX goal. [Project](https://github.com/DeterminateSystems/determinate-nix-action) |
| Upstream Nix alternative | `cachix/install-nix-action` | Preferred alternative if upstream Nix compatibility becomes an explicit requirement. Test it in a separate compatibility job first. [Project](https://github.com/cachix/install-nix-action) |
| CI-only Nix cache | Pilot `nix-community/cache-nix-action` | Documents compatibility with your existing Determinate installer; no additional service account or cache secret. The shared workflow can own keys, size limits and retention. [Project](https://github.com/nix-community/cache-nix-action) |
| Cache with less configuration | `DeterminateSystems/magic-nix-cache-action` | Viable alternative if store-snapshot restore/upload overhead is too high. Select backend and telemetry behavior explicitly. [Project](https://github.com/DeterminateSystems/magic-nix-cache-action) |
| Shared binary cache | `cachix/cachix-action` | Better fit when successful builds should be reused across repositories and on developer machines. Publish only from trusted jobs. [Project](https://github.com/cachix/cachix-action) |
| Flake-lock health | Keep `DeterminateSystems/flake-checker-action` | Already configured for both lockfiles and statistics disabled. Lock health complements builds; it does not establish that packages are vulnerability-free. [Project](https://github.com/DeterminateSystems/flake-checker-action) |
| Security scanning and Rust cache | Keep existing upstream actions and Nix-managed tools | Preserve CodeQL, dependency review, Scorecard, Rust cache, Cargo policy and release attestations. Centralize their setup where it actually matches. |
| Dependency updates | Keep Dependabot first | It already handles your configured ecosystems and updates reusable-workflow references. [GitHub support](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependabot-version-updates) |
| More configurable update policy | Reconsider Renovate later | Its GitHub Actions manager supports reusable workflows; its Nix manager is available. Shared presets can help when grouping and policy become more complex. Avoid two bots updating the same files. [Actions manager](https://docs.renovatebot.com/modules/manager/github-actions/), [Nix manager](https://docs.renovatebot.com/modules/manager/nix/) |

Pin the selected action code and also inspect what it downloads at runtime. An action SHA alone does not pin an installer URL, Nix distribution version, or external service. `nix-seal` release currently uses `nix-installer-action@v22` while its CI uses `determinate-nix-action`; make that intentional and test alignment before releasing. [Release workflow](https://github.com/nix-forge/nix-seal/blob/0663f4d45bd93e621d11fa9e76f1376be9e585c5/.github/workflows/release.yml).

The cache candidates are maintained, not abandoned alternatives: the checked stable releases were [cache-nix v7, January 8, 2026](https://github.com/nix-community/cache-nix-action/releases/tag/v7), [Magic Nix Cache v14, May 29, 2026](https://github.com/DeterminateSystems/magic-nix-cache-action/releases/tag/v14), and [Cachix action v17, March 18, 2026](https://github.com/cachix/cachix-action/releases/tag/v17). Release activity is not a security audit. Cache-nix and Magic use MIT licenses; Cachix's action uses Apache-2.0. Wrapper licenses do not determine hosted-service terms.

For the cache-nix pilot, include platform, Nix version and lockfile identity in the key, bound store size, and leave privileged cache purge disabled in PR jobs. Cache restoration can make a small job slower. If trying Magic v14 instead, its action metadata enables FlakeHub opportunistically; use `use-flakehub: disabled`, `use-gha-cache: enabled`, and `diagnostic-endpoint: ''` for an explicit GitHub-only configuration without diagnostics. [Cache-nix configuration](https://github.com/nix-community/cache-nix-action), [Magic v14 metadata](https://github.com/DeterminateSystems/magic-nix-cache-action/blob/v14/action.yml).

Determinate Nix is a distribution choice. If published modules promise upstream Nix compatibility, add an upstream compatibility job rather than assuming a successful Determinate run establishes it. The older installer action should not be selected on the assumption that it still defaults to upstream Nix. [Installer transition](https://determinate.systems/blog/installer-dropping-upstream/).

I would not switch to `nixbuild/nix-quick-install-action` just for an advertised installation speed advantage. Its supported model differs, including single-user installation and no self-hosted-runner support. The comparison needs your actual workloads. [Installer documentation](https://github.com/nixbuild/nix-quick-install-action).

`nix-community/nix-github-actions` is useful if maintaining build matrices becomes painful. It converts Nix attribute sets into Actions matrices. It does not replace repository governance, scanners, queue management, or release workflows. Keep the current small native matrices until generating them provides a concrete benefit. [Library](https://github.com/nix-community/nix-github-actions).

### The closest turnkey action is not a better baseline

I examined `OSSystems/nix-actions`, including release `v1.0.6`. Its default behavior builds every NixOS host, package, and development shell it discovers. That conflicts with nix-conf's intentional build limits and its requirement that the full desktop closure build on `desktop`. Its optional per-attribute checks require write permission and serialize those builds. The action also uses mutable tags for its own action dependencies, so pinning the outer action alone would not make the dependency chain immutable. [README](https://github.com/OSSystems/nix-actions), [release implementation](https://github.com/OSSystems/nix-actions/blob/v1.0.6/action.yml).

Those defaults are configurable, but enough would need overriding that the wrapper offers little advantage here. It also leaves the queue, review policy, scanners, and Rust assurance work to you. This is a fit assessment, not a claim that the action is malicious or unusable.

### Hosted alternatives

Garnix is worth a later trial if Nix build scheduling and shared caching become the limiting factors. Its default NixOS configuration builds require explicit exclusions to preserve the desktop placement rule. Hercules CI is worth considering if you want Nix-native CI with agents and controlled effects, but you operate the agents and compute. Either changes the CI operating model and still needs a plan for your existing GitHub security and non-Nix jobs. There is no measured evidence in this review that such a migration would pay for itself. [Garnix defaults](https://garnix.io/docs/ci/), [Hercules CI setup](https://docs.hercules-ci.com/hercules-ci/getting-started/).

Mergify can replace substantial merge automation and provides queue and CI visibility. Its queue is an alternative to GitHub's native queue, with documented ruleset incompatibilities. For five repos already using GitHub queues, I would first fix authentication and measure the remaining operational burden. [Mergify ruleset compatibility](https://docs.mergify.com/merge-queue/github-rulesets/).

## What the shared repository should own

| Centralize | Keep with each consuming repository |
| --- | --- |
| Flake-lock validation and common Nix setup | Flake outputs, exact build/check targets and repository tests |
| Common hooks workflow with a documented command contract | Submodule materialization and platform-specific preparation |
| CodeQL setup parameterized by language/build needs | Specialized Rust assurance, package updates, documentation and releases |
| Dependency-review configuration with event-aware refs | Trigger lists, schedules and path policy in short caller files |
| Metadata-only reviewer/auto-merge policy | Repository permissions and branch-protection configuration |
| One tested reconciler while it remains necessary | Explicit repository-specific queue workflow lists and eligibility rules |
| Release notes and supported input documentation | A pinned shared-workflow revision |

Start with a handful of workflows rather than one file with many mode flags. Add a small composite Nix-setup action only where custom jobs need steps before and after setup on the same runner. A shared workflow's ordinary checkout fetches the caller repository. If it needs scripts stored in `ci`, fetch that repository separately at a fixed revision or package those scripts in a pinned action; do not assume `./scripts` refers to the shared repo. [Reuse semantics](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows).

Keep Scorecard's publishing workflow local initially. Its publishing API restricts workflow configuration, permitted steps, runners and OIDC permissions. Centralization needs a real publication test before switching all five repos; wrapping it in an arbitrary setup action is unsuitable. [Scorecard restrictions](https://github.com/ossf/scorecard-action/blob/main/README.md#workflow-restrictions).

The Free plan is enough for public reusable workflows and your current repository-level protections. Do not base the design on organization-wide rulesets or mandatory organization workflows being available under that plan. Shared implementation and enforced adoption are separate problems. [Ruleset availability](https://docs.github.com/en/organizations/managing-organization-settings/creating-rulesets-for-repositories-in-your-organization).

## Improve queue automation before expanding it

The existing reconciler documents why it dispatches validation explicitly: enqueue events produced with `GITHUB_TOKEN` do not start the expected queue workflows. GitHub's current documentation confirms that most events created with this token do not create new runs. Explicit dispatch events are exceptions; certain PR events now create runs that require approval. [Trigger behavior](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).

My preferred target is a narrowly scoped GitHub App installation token for trusted queue admission and automated PR creation, while retaining ordinary `GITHUB_TOKEN` for CI. Use the official `actions/create-github-app-token`, restricted to the caller repository and the permissions the operation needs. The app key belongs only in the trusted automation job; it must never be exposed to PR build code. This adds a credential to manage, but may let GitHub deliver the native events and remove dispatch callbacks and status mirroring. [Official token action](https://github.com/actions/create-github-app-token).

This is a proposed simplification, not a verified replacement. First prove that app-authenticated admission starts `merge_group` checks and merges correctly for a passing bot PR, rejects a failing PR, handles a changed head, and recovers from a cancelled run. `gh pr merge` already understands native merge queues and auto-merge. [CLI semantics](https://cli.github.com/manual/gh_pr_merge).

Until that succeeds, extract the existing reconciler and its tests into one maintained implementation. Preserve its exact-commit validation, rerun handling and refusal to turn skipped jobs into passing checks. If you prefer to avoid an app key entirely, keeping this centralized implementation is a reasonable alternative.

Preserve the current human-only review policy during extraction. CODEOWNERS can replace reviewer-request workflows if you accept requests for bot changes too, but it is not equivalent to the current bot exclusions. Requiring code-owner approval for every change would also change unattended dependency merging. [GitHub review behavior](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/getting-started/managing-and-standardizing-pull-requests).

## Performance priorities

Moving YAML does not make a Nix build faster. The useful levers are cache reuse, build selection, runner choice, and repeated setup. These sampled successful merge-group jobs establish scale only; they are not benchmarks or medians.

| Repository | Sampled longest CI job | Source |
| --- | ---: | --- |
| nix-conf | 14m 41s, x86_64 Linux flake job | [Run](https://github.com/nix-forge/nix-conf/actions/runs/34160117554) |
| nix-seal | 11m 03s, x86_64 Linux Nix job | [Run](https://github.com/nix-forge/nix-seal/actions/runs/34164927624) |
| vpn-confinement | 6m 28s, x86_64 Linux flake job | [Run](https://github.com/nix-forge/vpn-confinement/actions/runs/34163962509) |
| nix-config-framework | 2m 13s, Darwin flake job | [Run](https://github.com/nix-forge/nix-config-framework/actions/runs/34163560577) |

No successful `nixpkgs-personal` CI run appeared in its latest 30-run sample. The sample included running, cancelled and failed CI, so I have not invented a comparable timing. Job durations exclude waiting for a runner and do not establish which proportion was installation, evaluation, substitution or compilation.

1. Measure cold and warm runs of the same revision with one cache implementation. Record wall time, queue delay, restore/upload time, cache size, and failures. Keep it only if the full job improves.
2. GitHub cache storage is scoped to repositories and refs. Creating `ci` does not create a cross-repository Nix store. Use a signed binary cache when sharing outputs between nixpkgs-personal, nix-conf, and local machines is the objective. [Cache access rules](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).
3. Keep native ARM Linux and Apple Silicon coverage. Preserve nix-conf's separate evaluator processes, selected Darwin packages, and desktop-host build restriction. A blanket `nix flake check` plus every host build would discard deliberate resource controls.
4. Investigate repeated root/submodule hooks and formatting only after mapping what each catches. Share immutable tool dependencies without silently deleting integration coverage.
5. Cancel obsolete PR runs, but keep caller and callee concurrency groups distinct. Do not let a generic cancellation rule interrupt trusted queue or release operations.

## Security and usability requirements for the migration

Use full commit SHAs for shared workflows and their action dependencies. Publish versioned releases and have Dependabot propose consumer updates. That means a central fix does not instantly change every caller; the update PRs are the deliberate rollout mechanism. Test on one consumer, roll forward, and revert a consumer's SHA if needed. [Pinning guidance](https://docs.github.com/en/actions/reference/security/secure-use), [immutable releases](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/using-immutable-releases-and-tags-to-manage-your-actions-releases).

Treat changes to privileged shared automation as changes affecting all five repos. Keep PR execution read-only, grant write/OIDC permissions only to jobs that need them, pass named secrets explicitly, and retain `persist-credentials: false`. Avoid an arbitrary shell-command input in any privileged workflow. Build caches published to developer machines must only receive outputs through a trusted publication path. [Privileged trigger guidance](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target).

Several current Dependabot groups are named `minor-patch` or similar but only specify wildcard patterns. Their names do not exclude major updates. Add actual `update-types` filters where supported and make automatic-merge eligibility explicit. I recommend human review for shared privileged-workflow changes, even when the update is semantically a patch. [Inspected config](https://github.com/nix-forge/nix-conf/blob/a273575944bad657f575780f6a446bbc12f5fa7c/.github/dependabot.yml), [group semantics](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference).

Keep the UI in GitHub. Give jobs stable, descriptive names and write a job summary with the target system, tested revision, shared workflow version, failed target, reproduction command and artifact links. Use annotations and retained failure logs instead of posting a comment on every run. `GITHUB_STEP_SUMMARY` supports Markdown summaries. [Summary support](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/workflow-commands-for-github-actions).

Reusable workflows can change displayed check names. Your protections and queue adapter depend on exact names, so capture the actual emitted checks on both PR and merge-group runs before switching required checks. If adding an aggregate gate, require every intended job explicitly and reject unexpected skipped or cancelled results. Do not equate a completed workflow with all required tests having executed.

## Rollout and decision criteria

1. Create the shared repository with the current installer and existing behavior. Extract flake-lock validation and one common workflow, with actionlint, zizmor, YAML checks and caller fixtures. Publish a tested first release.
2. Pilot on nix-config-framework, whose CI is comparatively small. Exercise normal PRs, Dependabot, merge groups, manual dispatch, failure and cancellation. Record check names and compare coverage.
3. Add one Nix cache in a separate change and benchmark the same workload. Add shared binary-cache publication only if cross-repository or local reuse justifies the service and credential setup.
4. Centralize the queue script and tests, then separately pilot app-token admission. Remove callbacks and scheduled fallback only after native events prove reliable. Keep current protection requirements intact during the experiment.
5. Migrate vpn-confinement, then nixpkgs-personal and nix-seal. Migrate nix-conf last because it has the most specialized build constraints. Leave Scorecard publishing and specialized releases local until separately validated.

Call the migration successful when a common policy fix needs one implementation change, consumer upgrades arrive automatically, required checks still reject failing PRs and merge groups, no PR job gains privileged credentials, and measured build latency stays within the baseline or improves. Reduced YAML is useful, but preserving coverage and reducing maintenance are the actual goals.

Confidence is high in the shared-workflow architecture and the need to consolidate the queue code. Cache choice and replacing the queue adapter remain experiments. This research did not benchmark alternative runners/caches, validate a GitHub App deployment, or perform a full security audit. No workflows, repository settings, apps, or remote repositories were changed.
