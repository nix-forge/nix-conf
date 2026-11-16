# NixForge CI runtime and cache audit

Reviewed: 2026-11-15. The timing window is 2026-11-12 18:21:42 UTC through
2026-11-15 18:21:42 UTC. Scope: all eight NixForge repositories, every workflow
and event type created in that window, and all jobs returned for those runs.
This supplements the [earlier efficiency research](ci-efficiency-research.md).

## Answer

Prioritize broken updater preparation, the expensive Darwin application artifact
path, and cheap checks before native builds. Improve exact upstream substitution
and measure a deliberately seeded output cache before removing useful tests.

The inventory contains 983 workflow runs and 2,969 jobs, accounting for 323.02
raw runner-hours through the cutoff. `nix-conf` and `nixpkgs-personal` account
for 99.24% of that time. These are summed execution durations, not elapsed
waiting time, billed minutes, or a monetary estimate. Parallel jobs overlap.

| Repository | Runs | Jobs | Raw runner-hours |
| --- | ---: | ---: | ---: |
| nix-conf | 366 | 1,677 | 170.77 |
| nixpkgs-personal | 525 | 1,178 | 149.80 |
| nix-homelab | 16 | 28 | 1.90 |
| nix-seal | 22 | 28 | 0.42 |
| ci | 13 | 14 | 0.04 |
| nix-config-framework | 14 | 15 | 0.04 |
| .github | 14 | 15 | 0.03 |
| vpn-confinement | 13 | 14 | 0.03 |

The complete API collection had no retrieval errors. One job was still running
at the cutoff; its observed time is included as a lower bound. Skipped jobs have
zero execution time. Aggregates below distinguish failures and cancellations
rather than treating them as successful benchmark samples.

## What is holding up the current pull request?

In [PR 326's current run](https://github.com/nix-forge/nix-conf/actions/runs/43740475224),
the ten Linux native shards completed in approximately 2–10 minutes. Submodule
hooks took 17.6 minutes. The
[Darwin job](https://github.com/nix-forge/nix-conf/actions/runs/43740475224/job/132892461139)
had run for 61.4 minutes at the cutoff:

- Assigned native checks passed in 34.9 minutes.
- The later Handy identity/signature step had been active for 22.9 minutes.
- Setup, credential preflight, native process tests and Zen verification account
  for the remaining observed time. Further native steps were still pending.

The running Handy step first realizes `checks.aarch64-darwin.handy-artifact`,
then realizes the test shell and executes the native proof. Active-job metadata
cannot separate those three subphases. This is evidence of a slow step, not a
stalled process or a completed 22.9-minute build.
[Workflow source](https://github.com/nix-forge/nix-conf/blob/9e24d0b1d0a9c375a5a4530a91927ec07fc0f145/.github/workflows/ci.yml#L704).

The shared runner can skip an unchanged check by comparing derivation paths.
That skip does not place its output on a fresh runner. The unconditional later
artifact build can therefore pay the unchanged package's realization cost.
Keep the native signature/microphone proof. Time artifact realization,
test-environment realization and native execution separately; then optimize the
expensive phase. The repair is already a separate sealing derivation over the
original Handy package, so prefer substituting the unchanged upstream package
and caching the small repaired result where that is sufficient.
[Repair source](https://github.com/nix-forge/nix-conf/blob/9e24d0b1d0a9c375a5a4530a91927ec07fc0f145/overlays/temporary/handy-darwin-signature.nix).

## Repeated work and failures

### Fix the package updater before adding caches

All 63 updater jobs across three daily runs failed with the same Nix error:
`revCount` was unavailable because the Git checkout was shallow. All 63 failed
job logs were inspected; no log retrieval failed. The 63 updater jobs and three
successful discovery jobs consumed 12.09 runner-hours combined. The sample
covers these complete runs:

- [November 13 updater run](https://github.com/nix-forge/nixpkgs-personal/actions/runs/43424469973)
- [November 14 updater run](https://github.com/nix-forge/nixpkgs-personal/actions/runs/43590805516)
- [November 15 updater run](https://github.com/nix-forge/nixpkgs-personal/actions/runs/43711749849)

The update job omits `fetch-depth`, then enters the full development shell before
running the updater. `actions/checkout` defaults to one commit; Nix's Git source
metadata needs history for this revision-dependent evaluation. A cache might
shorten setup but would not repair the deterministic failure.
[Updater workflow](https://github.com/nix-forge/nixpkgs-personal/blob/e25e8ef1e7bc5340e0115c50bdf6fb519649ce8f/.github/workflows/update-packages.yml#L54),
[checkout behavior](https://github.com/actions/checkout#usage),
[Nix Git metadata](https://nix.dev/manual/nix/2.35/command-ref/new-cli/nix3-flake.html).

The package owner should use a full-history update checkout and test required
metadata before realizing the expensive shell. A subsequent minimal updater
shell could avoid incidental dependencies while retaining pinned tools. Do not
fabricate `revCount` for version identity. All updaters currently use macOS;
select Linux only for updaters whose actual platform requirements permit it.

### Gate expensive work on the smallest useful static check

Eight root runs with failed repository hooks also launched native check jobs
that consumed 6.95 runner-hours. In the concrete
[type-check failure](https://github.com/nix-forge/nix-conf/actions/runs/43740060565/job/132891022478),
Linux native check steps started before the failing `ty` result arrived.
This is an opportunity for an early gate, not a guarantee that all 6.95 hours
could be eliminated without any latency tradeoff.

A small pinned type/static gate should precede costly native work. Moving its
existing execution owner avoids adding another duplicate lint pass. Waiting on
the full root hook job is simpler but delays successful changes by its entire
runtime. Preserve required aggregate status names and make upstream failures
explicit rather than accepting an accidentally skipped matrix as validation.
[Root job dependencies](https://github.com/nix-forge/nix-conf/blob/9e24d0b1d0a9c375a5a4530a91927ec07fc0f145/.github/workflows/ci.yml#L483).

### Target the expensive workload, not the workflow count

Of the 323.02 runner-hours, 72.16 belonged to cancelled jobs and 26.31 to failed
jobs. Some diagnostic failures were intentional; cancellation can save the
remaining cost of superseded work. These totals are not all recoverable waste,
and disabling cancellation would be the wrong inference.

Queue reconciliation contributed 667 runs but only 1.25 runner-hours. Removing
that automation would target less than 0.4% of observed execution time while
weakening queue recovery. The expensive work is native package/check realization.
One package Darwin shard spent 351.6 minutes in affected-package builds before
cancellation; an earlier successful counterpart spent 276.5 minutes in that phase.
[Long cancelled shard](https://github.com/nix-forge/nixpkgs-personal/actions/runs/43362659423/job/131686011694),
[long successful shard](https://github.com/nix-forge/nixpkgs-personal/actions/runs/43324932897/job/131564234577).

## Cache findings

### Upstream Nix binary substitution is already working

Completed logs contain many `copying path ... from https://cache.nixos.org`
records, including the current
[Linux native shard](https://github.com/nix-forge/nix-conf/actions/runs/43740475224/job/132892461176),
[submodule hooks](https://github.com/nix-forge/nix-conf/actions/runs/43740475224/job/132892461075),
and an earlier
[Darwin native job](https://github.com/nix-forge/nix-conf/actions/runs/43722977605/job/132838744253).
This rules out the claim that upstream caching is simply disabled. Copy-line
counts are not a cache hit rate: logs can repeat failure tails, and one output
can have multiple paths.

Nix substitutes an exact store output. Matching a package name and version is
insufficient when platform, package-set pin, toolchain, dependencies or patches
differ. Adding a provider cannot supply an output that provider never built.
[Configuration reference](https://nix.dev/manual/nix/2.35/command-ref/conf-file.html#conf-substituters),
[derivation model](https://nix.dev/manual/nix/2.35/store/derivation/).

A concrete historical example is the root REA shard that built Node 24.22.1
from source and reached its three-hour limit. The merged package work subsequently
selected a qualified cached Node runtime; do not propose that already-completed
repair as new work.
[Old cold runtime job](https://github.com/nix-forge/nix-conf/actions/runs/43621272041/job/132527467008),
[merged Darwin cached-runtime change](https://github.com/nix-forge/nixpkgs-personal/pull/234).

The next useful audit unit is the expensive dependency's exact derivation and
platform. Prefer a compatible upstream cached recipe/toolchain over rebuilding
it under an incidental override. Retaining a vendor's own pin can improve its
substitution coverage, but changing all `follows` globally can introduce other
incompatibilities. Hyprland explicitly documents the cache cost of replacing its
Nixpkgs input. Required compositor patches still need their own builds.
[Hyprland cache guidance](https://wiki.hypr.land/nix/cachix/).

### Supplementary cache policy is not consistently effective

Current root logs warn that the flake's `extra-substituters` and
`extra-trusted-public-keys` are ignored. The native build step explicitly supplies
the Hyprland provider, while the default NixOS cache still works. Installing the
repository's host cache module does not configure an ephemeral runner.
[Root flake providers](https://github.com/nix-forge/nix-conf/blob/9e24d0b1d0a9c375a5a4530a91927ec07fc0f145/flake.nix#L6),
[workflow-owned native settings](https://github.com/nix-forge/nix-conf/blob/9e24d0b1d0a9c375a5a4530a91927ec07fc0f145/.github/workflows/ci.yml#L671).

Record only the effective provider/key allowlist and platform in future cache
receipts. Supply needed providers through reviewed workflow-owned policy; do not
accept arbitrary pull-request-controlled flake settings merely to remove warnings.
Provider availability and the usefulness of each provider remain separate checks.

### Existing GitHub caches are not the Nix output-store pilot

A read-only cache inventory taken after the timing cutoff found installer,
flake-checker, CodeQL, Rust and other tool caches across the organization, but
zero entries with the shared Nix-store pilot's `nix-v1-` prefix. This inventory
is a later snapshot, not proof that no such cache ever existed. It also does not
inspect external binary-cache services.

Root ordinary PR/merge-group jobs disable the store pilot. It is available only
for a manual cache-enabled dispatch. The shared action saves on a default-branch
push or default-branch dispatch, not ordinary PR/merge-group execution. Root has
no ordinary push-triggered full CI producer. A deliberate default-branch seed is
possible, but it must actually run and retain useful outputs before consumers
can benefit.
[Root opt-in configuration](https://github.com/nix-forge/nix-conf/blob/9e24d0b1d0a9c375a5a4530a91927ec07fc0f145/.github/workflows/ci.yml#L642),
[pinned shared cache action](https://github.com/nix-forge/ci/blob/1a6dfe0b851c69ad30169977e014bd45029e9c55/actions/setup-nix/action.yml).

Before enabling it broadly, address three design constraints:

1. Root native shards and guide jobs share a per-system scope without a partition
   or workload identifier. A single immutable cache entry does not merge every
   shard's store. Compare separate workload keys with a deliberately seeded shared
   dependency closure; both have storage/transfer costs.
2. The restore prefix includes every matched lockfile hash. An unrelated nested
   lock change prevents that prefix reuse. Keep exact-output validation even if
   a broader dependency restore prefix is benchmarked.
3. `gc-max-store-size: 2G` is a garbage-collection target, not a guaranteed archive
   size. Roots can retain more, while useful unrooted `--no-link` outputs may be
   collected. Measure retained outputs, archive size, restore/save time and GC.

GitHub dependency caches are repository scoped; identical keys do not create an
organization-wide binary cache. A signed owned binary cache can share expensive
identical patched outputs across repositories, but needs trusted writers,
credential separation and redistributable-output policy. Cache package/dependency
results without treating them as proof that a current native runtime check ran.
[GitHub cache restrictions](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching),
[pinned cache action](https://github.com/nix-community/cache-nix-action/blob/7df957e333c1e5da7721f60227dbba6d06080569/action.yml).

## What can be consolidated safely?

Assign one CI owner to provably identical static invocations. Root hooks and
`python-quality` both execute Ruff, `ty` and compileall; compare their source scope,
configuration and execution environment before consolidating them. Keep history
scanning, publication canaries and distinct sandbox/native assertions.
[Python quality script](../../flake/dev/scripts/python-quality.sh),
[hook definitions](../../flake/dev/git-hooks.nix).

Improve source filtering where a derivation consumes the entire repository for
a narrower check. Verify that new source files, schemas and configuration remain
included. Existing filtered Python tests and stylesheet checks supply patterns;
this is an invalidation improvement, not permission to omit relevant files.

Keep the existing same-derivation skip mechanism. In the current sampled x86
shard, 16 of 18 checks were skipped correctly, while two base evaluations exceeded
60 seconds and conservatively rebuilt. Earlier missing-attribute fallbacks mostly
involved checks newly introduced after the base commit and were appropriate.
Investigate bounded base/head derivation manifests to reduce repeated evaluation;
preserve isolated evaluation memory bounds, per-check errors and rebuild on unknown
inputs. The double-JSON `fromJSON` encoding in the runner is intentional and correct.
[Shared runner](https://github.com/nix-forge/ci/blob/1a6dfe0b851c69ad30169977e014bd45029e9c55/scripts/run-flake-checks.py).

Do not remove an aggregate that is already absent from hosted CI. The root already
excludes `generated-artifacts`, avoids a second Linux Python suite and groups the
shared Determinate consumers. Native Darwin process tests intentionally cover a
boundary unavailable inside its build sandbox. Runtime, recovery, credential and
signature checks should remain until an alternative proves the same property.
[CI output ownership](../../hosts/shared/local/flake/deploy.nix).

## Recommended implementation order

| Priority | Owner | Change | Acceptance evidence |
| --- | --- | --- | --- |
| 1 | Package repository | Full-history updater checkout and metadata preflight; then a minimal updater shell | All 21 updaters reach their actual work; ordinary no-update runs succeed; revision identity remains correct |
| 2 | Root | Time Handy artifact, test shell and native proof separately; use exact available upstream outputs | Identical installed artifact and all native signature/microphone assertions; lower measured critical path |
| 3 | Root/shared CI | Put the smallest existing static/type gate ahead of expensive native work | Known lint failures launch no native payload; successful changes retain every check and acceptable added latency |
| 4 | Root/shared CI | Audit effective supplementary providers and exact missing dependency outputs | Signed substitute-only probes succeed for intended unchanged outputs; no trust broadening from PR input |
| 5 | Shared CI/callers | Small trusted seed plus read-only consumer cache pilot; repair scopes and retention | Net savings after restore/GC/save, useful output retention, exact platform/lock identity and safe writer policy |
| 6 | Shared CI/package/root | Bounded derivation manifests, source filtering and identical static-pass consolidation | Same selected checks and failures, fewer evaluations/rebuilds, bounded peak memory |

Benchmark one treatment at a time against a frozen root/submodule/lock manifest,
with a cold control and at least two restored runs per native platform. Measure
both total runner work and PR critical path. Preserve all failure evidence and
check cases; no percentage speedup is established by this read-only audit.

## Validation and limits

GitHub run/job/cache APIs, completed logs, exact workflow sources and official
Nix/GitHub documentation were inspected. All 983 run records have run attempt 1;
job IDs are unique across the 2,969 returned records. All 63 failed updater logs
were checked. Other large logs were sampled by expensive phase and platform;
they are not a complete derivation-level census of every historical build.

Execution durations are clipped to the timing cutoff. Job creation-to-start
delays are a different metric and can include scheduling/dependency delays; they
are not counted as build execution or claimed to be pure runner-capacity queues.
Cancelled/failed samples, changed check inventories and evolving package pins
prevent treating historical medians as a controlled before/after benchmark.

No running check was cancelled, stopped, rerun or reconfigured. No build, cache
seed, deployment or activation was started. These are reviewed recommendations;
workflow implementation and cache savings remain to be validated separately.

## Follow-up: controlled Linux static-cache pilot

After implementation, the trusted main-branch producer completed on root
`bb481eb2fab6bb064cee8efef4c0ec0653cd44b8`. One initial Nix-store cache miss
was followed by two sequential runs restoring the exact primary keys. All three
used Determinate Nix 3.24.2 / Nix 2.35.3 and the same root, locks and workloads.
The installer's separate download cache is not counted as a Nix-store hit.

| Producer workload | Initial job, seconds | Exact restore 1, seconds | Exact restore 2, seconds | Initial compressed archive, bytes |
| --- | ---: | ---: | ---: | ---: |
| Python tooling | 61 | 36 | 38 | 596,914,202 |
| Lint tooling | 167 | 76 | 50 | 1,377,864,109 |

Job times include checkout, setup, closure realization and post-job processing;
they exclude time before the job started. Initial cache post-actions took about
12.2 seconds for Python and 29.6 seconds for lint. Exact primary hits did not
write new archives. The lint profile retained about 4.79 GB of store objects
after collection: the 2 GiB GC target is not a hard cap on a pinned closure.
The retained Python store measured about 1.85 GB.
[Initial producer](https://github.com/nix-forge/nix-conf/actions/runs/43808629932),
[first restored run](https://github.com/nix-forge/nix-conf/actions/runs/43818987709),
[second restored run](https://github.com/nix-forge/nix-conf/actions/runs/43819853277).

These small controlled samples support retaining the Linux static-tool pilot.
They measure producer preparation, not a full PR or native application build.
Runner variation remains visible between the two restored lint runs; no general
CI speedup percentage or native-platform benefit follows from these samples.
