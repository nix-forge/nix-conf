# Efficient Nix build queues

Reviewed: 2026-10-12. Scope: Nix 2.34.9 documentation, current Nixpkgs manual,
Linux cgroup v2 documentation and systemd v261.2 source documentation.

## Answer

Keep native builds native. For a foreign architecture, use native compiler tools
and cross compilation when the recipe supports it. Queue one package at a time
with the host compiler budget under the current memory policy. The follow-up
[hardware investigation](build-hardware-utilization-research.md) raises the
desktop default to eight compiler jobs. Freeze the launcher and
its input source before submitting the job. Reuse completed outputs and retain
their GC roots. These are orchestration improvements, not a measured claim of
faster compilation.

## Findings and sources

### Build tools and runtime programs need separate platforms

Nixpkgs defines `buildPlatform` as the platform that builds the package and
`hostPlatform` as the platform that runs its output. Native build helpers belong
on the build platform. Tests that execute installed programs need the host
platform. Nixpkgs recommends `stdenv.buildPlatform.canExecute
stdenv.hostPlatform` for deciding whether an ordinary test suite can run.
[Nixpkgs platform parameters and cross-compilation FAQ](https://nixos.org/manual/nixpkgs/stable/#chap-cross).

The resulting project policy is native-first selection. Architecture-neutral
checks, such as linting or inspecting ELF headers, use native helpers. Foreign
CLI and GUI programs require an explicit emulator or a suitable native runner.
A native display server does not make a foreign executable native. Keep target
runtime libraries associated with that executable and avoid applying their
loader paths to native helper processes. A foreign native package set can supply
cached runtime libraries, but missing substitutes can start emulated dependency
builds. It is not a substitute for selecting a native cross compiler.

### Job count is not CPU utilization

`--cores` sets `NIX_BUILD_CORES`, which the builder can use to choose its internal
parallelism. `--max-jobs` independently controls simultaneous local derivations.
Neither guarantees a utilization percentage. Configured substituters can supply
outputs instead of compiling them.
[Nix build settings](https://nix.dev/manual/nix/2.34/command-ref/conf-file.html#conf-cores).

The earlier four-job setting and one derivation per turn were conservative project choices,
not universal optimal values. The existing application pilot reached the memory
pressure boundary, as recorded in the
[builder review](arm-linux-builder-research.md#completed-pilot-and-default-workflow).
Increasing parallelism without more memory can add reclaim work. The kernel
documents that `memory.high` throttles allocations and applies reclaim pressure;
`memory.max` can invoke the cgroup OOM killer.
[Linux memory controller](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html#memory).

CPU weights distribute capacity under contention. CPU quotas impose a ceiling
relative to one CPU, so host-wide percentage calculations must include the CPU
count. The queue's user processes and daemon builders can occupy separate
cgroups. Independent ceilings on those groups do not create one shared ceiling.
[systemd resource-control source](https://github.com/systemd/systemd/blob/v261.2/man/systemd.resource-control.xml).

### Freeze a job before it waits

`nix flake archive` copies the flake and its inputs into a store. Its JSON output
identifies the immutable paths. Archive the intended source once, retain the
inputs, and build that store snapshot after the queue grants a turn. Copy the
launcher and any non-flake coordinator code into the same immutable submission.
Editing the working checkout should affect the next submission.
[Nix flake archive](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-flake-archive.html).

This is an orchestration recommendation. Archiving alone neither protects every
input from garbage collection nor freezes mutable files outside the flake.
Retain required sources and completed outputs through explicit GC roots.
[Nix garbage-collection roots](https://nix.dev/manual/nix/2.34/command-ref/nix-store/gc.html).

Normal `nix build` reuses matching outputs or substitutes them. Its output links
retain successful results. `--rebuild` requests an additional build and comparison;
reserve it for deliberate reproducibility work. Keep a distinct output-link
prefix for each job so later builds do not replace earlier retained results.
[Nix build behavior](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-build.html).

### Let the owner wait and cancel

A pidfd becomes readable when its process exits and works with `poll`, `select`
or `epoll`. Use this lifecycle notification for child completion, with bounded
resource sampling alongside it. Record queue wait separately from execution.
[Linux pidfd documentation](https://man7.org/linux/man-pages/man2/pidfd_open.2.html).

Systemd's `KillMode=control-group` terminates the processes inside the owned unit.
Use an owned unit or process group for coordinator cleanup. A daemon build may
live outside that unit, so cgroup cancellation alone does not establish that
the builder stopped. Preserve unrelated queued work and completed outputs.
[systemd kill behavior](https://github.com/systemd/systemd/blob/v261.2/man/systemd.kill.xml).

## Validation and limits

This review read primary documentation and the existing pilot record. It ran no
builds, evaluations, tests or activation. It does not establish a new throughput
benchmark, universal cross-compilation support or foreign GUI hardware coverage.
Keep release profiles and package test semantics unchanged when improving the
queue. A check that did not run must not be reported as passed.

## Implication for this repository

Use the shared workload queue for heavy desktop work, submit each package
separately, and select the build and host platforms explicitly. Keep the configured host compiler parallelism, one derivation at a time,
and the current memory limits. Reuse
completed results instead of restarting successful work. The
[desktop memory operations guide](../operations/desktop-memory-management.md)
owns queue and activation policy.

## Remote waits and queue placement

Reviewed: 2026-10-13. A remote compilation can occupy little desktop CPU while
its local client retains an exclusive desktop queue slot. This is an
orchestration problem. Raising compiler counts does not release that lock.
Separate the local evaluation phase from the remote realization phase.

Nix documents `nix path-info --derivation INSTALLABLE` as a way to obtain the
store derivation without building or substituting its output. Evaluate the
frozen source and record the resulting derivation inside `workstation-task`.
Import-from-derivation can still require evaluation-time realization; a
production launcher must account for that rather than treating every evaluation
as resource-free.
[Nix path-info](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-path-info.html).

Copy the derivation with `nix copy --derivation --to ssh://REMOTE "$drv"`.
This copies its store closure and selects the derivation instead of its outputs.
It does not request compilation of those outputs. Destination substitution can
reduce transfers when available.
[Nix copy](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-copy.html).

`nix-store --query --requisites "$drv"` returns the derivation's source closure.
Existing outputs of dependency derivations are excluded unless
`--include-outputs` is requested. Copying the source closure is enough to let
the remote machine realize the graph. It may have to substitute or build inputs
that the desktop already has. For reuse, copy the existing dependency outputs
as an additional bounded transfer. Do not use `--force-realise` while discovering
them, because that can start builds locally.
[Nix store closure queries](https://nix.dev/manual/nix/2.34/command-ref/nix-store/query.html).

On a verified native Darwin host, realize the copied derivation with a command
of this form. The launcher must validate the store path and choose an absolute,
unique result-root path before constructing the remote command.

```sh
ssh "$remote" "nix-store --realise '$drv' --builders '' \
  --max-jobs 1 --cores '$remote_cores' \
  --add-root '$remote_result' --indirect"
```

`nix-store --realise` substitutes available outputs and builds the remaining
dependencies. `--add-root` retains successful results. Running that command on
the remote host places compilation there. Root the input derivation and source
closure using the launcher's explicit GC-root mechanism while waiting. Do not
attempt to root an input derivation on the desktop by realizing it, because that
requests its output build.
[Nix store realization and roots](https://nix.dev/manual/nix/2.34/command-ref/nix-store/realise.html).

Release the desktop exclusive slot before the SSH wait. Keep one remote job
per destination, bounded client memory and transfer concurrency, recorded status,
and explicit cancellation ownership. Retain the remote result before copying it
back. Copying outputs does not activate or install them.

An alternative is a separate bounded remote-client lane alongside the local
lane. It reduces migration work for existing launchers, but requires proof that
the accepted jobs cannot compile locally. `--max-jobs 0` alone is insufficient:
Nix documents an exception for derivations with `preferLocalBuild = true`.
Examine the transitive derivation graph and prevent fallback to local builds.
[Nix max-jobs setting](https://nix.dev/manual/nix/2.34/command-ref/conf-file.html#conf-max-jobs).

Both lanes should share a parent workload memory budget, with a tighter child
limit for the remote client. Systemd controls are hierarchical, so a child cannot
exceed its parent's limit. Independent sibling limits without a common parent
do not enforce a shared ceiling.
[Systemd resource controls](https://github.com/systemd/systemd/blob/v261.2/man/systemd.resource-control.xml).

The staged evaluation and direct remote realization workflow has the clearest
placement guarantee. The separate lane can safely overlap a verified lightweight
remote wait with local compilation when its graph and parent budget are enforced.
Neither approach permits Linux compilation on a Darwin host. This addendum read
documentation only and ran no builds, evaluations, checks, or transfers.

### Implemented command and verification

Implementation review: 2026-10-13. `just remote-realise` queues local inspection
and derivation copying, then realizes the package directly on its matching native
remote host. It rejects an outer desktop workload scope and desktop system
closures, which retain their dedicated build recipes. The helper captures the
root names printed by `--add-root` and queries store output paths separately for
receipts. Output roots remain on the remote host. Its metadata adapter accepts
legacy maps and version-2/version-4 envelopes; the installed Nix
version-4 response was inspected directly, including its basename keys. Unknown
formats and mismatched records fail before copying or building.

Nineteen focused regression cases passed for placement, failure propagation,
output receipts and source archives; the affected Python code passed Ruff.
Native remote cached-output realization and rooting were exercised without a
new compilation. A subsequent live cached-output run also passed the full
queued inspection and derivation-transfer path, followed by native remote
realization and an output receipt. These results establish placement and
transport behavior, rather than a throughput benchmark or completion of
unrelated package matrices.

The Linux package launcher now enables `--print-build-logs`. Compiler output and
build/check phase transitions go to standard error while standard output keeps
the JSON receipt. This makes lengthy compilation visible without adding another
build or changing the package's test profile. Existing immutable jobs retain
their original command; the change applies to future submissions.
[Nix build logging](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-build.html).

The launcher review extracted its compiler-budget calculation and retained the
configured host limit, CPU affinity bound and automatic headroom policy. Five
additional cases cover the eight-job default, a lower configured limit,
restricted affinity and automatic settings. All 24 focused cases passed; the
changed launcher and tests passed Ruff lint and formatting checks. This verifies
budget selection and helper behavior, without measuring a compilation speedup.

## Development efficiency follow-up

Reviewed: 2026-11-09. Scope: current working-tree queue and workflow sources,
Pueue 4.0.4, and the native package publication dependency. This section supersedes
older implementation-status and fixed compiler-count recommendations above;
older measurements remain dated evidence, not current performance estimates.

### Fix the limiting phase

Distinguish four outcomes before changing resources:

- A queued wrapper can wait on the shared execution lock without running a build.
- Admission can wait on host reserve, an ancestor limit, or pressure; enough
  host-wide available memory does not establish ancestor headroom.
- A payload can fail because its tool invocation, environment, source snapshot,
  or namespace is wrong. More RAM does not repair these failures.
- A build can spend time compiling or substituting. A long running status alone
  does not establish a stall or a cache failure.

The [job runbook](../operations/workstation-jobs.md) owns the installed contract.
The [adapter](../../modules/home/services/workstation-jobs-assets/workstation_job.py)
and [memory controller](../../modules/home/services/workstation-jobs-assets/workstation_memory.py)
already support waiting admission and explicit memory ranges. Keep the existing
implementation; do not reimplement adaptive scheduling from the historical
[proposal](elastic-workstation-memory-research.md).

### Prioritized improvements

1. Validate the frozen launcher before submitting expensive work: interpreter
   and required plugins, supported command flags, source/hash manifest, output
   existence, selected Nix installable and namespace ownership requirements.
   Use the repository's declared test environment; disabling automatic pytest
   plugin discovery follows [the existing check builder](../../tests/python-check.nix)
   and avoids conflicts with explicitly selected plugins. Preflight must not
   run the payload's financial, publication or deployment side effects.
2. Select a whole-job minimum from comparable observed peaks at the configured
   compiler parallelism. Use a qualified minimum/maximum request when supported;
   do not use the generic profile floor as proof that a workload fits there.
   Keep daemon work separate from confined tests and retain the host reserve,
   pressure, swap and ancestor checks.
3. Reuse compatible accepted outputs and toolchains, with exact lock/source/
   platform identity and retained roots. Evaluate the needed platform attributes
   together instead of repeating broad host or cross-system evaluation. Do not
   replace mandatory rebuild/reproducibility checks with cache hits.
4. Use the existing staged remote-realization path above for suitable package
   work: freeze/evaluate/transfer in the local allocation, then release it before
   waiting on the destination's own finite allocation. Desktop system closures
   retain their dedicated desktop placement. Darwin output does not qualify a
   Linux package.
5. Diagnose the current publication dependency at its owner. Native package
   materialization and platform verification remain required even when the
   downstream configuration edit is only a gitlink. Keep one owner and use
   check-completion notifications instead of repeatedly polling the same state.
6. Keep scheduler backfill as a separate design, rather than an emergency lock
   change. A large admitted wrapper waiting for capacity can delay smaller jobs.
   Safe overlap needs a shared reservation authority, bounded fairness, atomic
   admission and preserved launch/drain proofs; raising Pueue group parallelism
   or dropping a shared lock alone does not provide them.

### Deadline scope and blocked-state diagnosis

The [supervisor](../../modules/home/services/workstation-jobs-assets/workstation_job.py)
starts its monotonic timeout at wrapper execution and records earlier scheduler
queue time separately. A Pueue-queued or deliberately stashed request therefore
has not consumed that executor budget yet. Clarify this before estimating a
release window. A future total-deadline feature needs a distinct immutable field,
backward compatibility, clock-anomaly handling, and tests proving that an expired
request never launches. Do not silently reinterpret existing recipes.

The daemon guard remains present: the desktop runner expresses its required host
headroom as a one-MiB sentinel allocation plus the remaining reserve. The absence
of a direct shell comparison against the full guard is not evidence it vanished.
Read the runner and memory controller together when diagnosing admission.

A useful next diagnostic increment would expose the current lock/capacity phase,
the finite ancestor limiting room, frozen deadline scope and launch-claim state.
It must remain read-only and retain every unresolved job. Historical missing
receipts belong to their original owner; neither age nor low CPU justifies deleting
claims, replaying a payload or calling the host globally clean.

Pueue's scheduler orders queued tasks using group slots, priority and dependencies;
it does not inspect this runner's memory or locks.
[Pueue 4.0.4 scheduler](https://github.com/Nukesor/pueue/blob/v4.0.4/pueue/src/daemon/process_handler/spawn.rs).
A backfill scheduler can protect older reservations while admitting smaller work,
but it needs defensible resource and runtime estimates.
[Slurm backfill model](https://slurm.schedmd.com/sched_config.html#backfill).
These sources explain why more queue groups alone would not solve admission.

### Acceptance and evidence

Record submission, admission, payload start/end and scope drainage separately.
Compare queue delay, setup failure frequency, evaluation time, build time and
closeout overhead only for comparable immutable increments. Missing memory
peaks remain unknown; do not invent a safe minimum from an absent measurement.
A faster launcher or shorter diagnostic response is not proof of a faster build.

This follow-up inspected source, existing receipts, GitHub check metadata and
primary documentation. It launched no check, build or workflow, changed no
scheduler/service settings, and established no new throughput benchmark. Runtime
telemetry is needed before selecting a capacity or cache redesign.
