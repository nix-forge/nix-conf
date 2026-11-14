# Adaptive memory admission for workstation jobs

Reviewed: 2026-11-07. Scope: the current queue and desktop executor, Pueue 4.0.4,
Linux cgroup v2 and PSI, systemd 262, upstream Nix 2.34.8/2.35.4, and native
macOS constraints. This is the historical implementation proposal, not a description of the current
queue. Waiting admission, explicit memory ranges and upward growth now exist in
the working-tree implementation; the [job runbook](../operations/workstation-jobs.md)
and [efficiency follow-up](build-queue-efficiency-research.md#development-efficiency-follow-up)
describe the current interface and next steps. Activation remains host- and
revision-specific and needs separate runtime evidence.

## Answer

Extend the existing executor with **waiting admission, explicit memory ranges,
and controlled upward growth during execution**. Retain Pueue, immutable recipes,
shared locks, containment and recovery receipts. The earlier
[scheduler comparison](workload-scheduler-research.md) covers scheduler choices;
switching schedulers would not remove these responsibilities.

The intended behavior is:

- Insufficient RAM: retain the request and wait with visible status,
  cancellation and a deadline, without launching its payload.
- Enough RAM for the workload's verified minimum: choose an allowance that fits
  current host and ancestor headroom, up to its declared ceiling.
- More RAM during execution: permit controlled growth within that ceiling when
  useful. Additional compiler workers require separate application support.
- Less than the minimum or excessive host pressure: continue waiting. Admission
  expiry means no payload launched; an OOM or failed payload stays a failed attempt.

A build cannot reliably complete with any arbitrary amount of remaining RAM.
Its minimum must cover its actual working set at configured compiler parallelism,
including link and test phases. Until qualified, keep its fixed request and
improve waiting. Preserve complete acceptance checks and compiler parallelism.

## Findings and sources

### Existing behavior and integration points

These are observations of working-tree source, including existing uncommitted
changes, inspected on the review date. They do not describe HEAD alone.

| Component | Current behavior | Extension needed |
| --- | --- | --- |
| [Typed desktop policy](../../hosts/nixos/desktop/local/workload-policy.nix) | Confined requests 1–8 GiB, default 4 GiB, host reserve 2 GiB; aggregate high/max 8/10 GiB. | Own wait policy, margins and elastic bounds here. Keep reviewed aggregate limits initially. |
| [Desktop runner](../../homes/desktop/local/workstation-task.sh) | Acquires shared locks, samples capacity, then exits 75 on insufficient headroom. | Wait and select grants under the same allocation authority; preserve lock order. |
| [Queue adapter](../../modules/home/services/workstation-jobs-assets/workstation_job.py) | Persists one memory request; native backends reject low capacity in `_supervise`, desktop delegates to the runner. | Version recipes/receipts and distinguish waiting from payload execution. |
| [Queue options](../../modules/home/services/workstation-jobs.nix) | Profile minimum/maximum bound allowed requests, rather than each job's viable working set. | Add explicit per-job ranges; do not assign every job the profile floor. |
| [Private-store builder](../../homes/desktop/local/scripts/workstation_nix.py) | Builds inside containment, keeps compiler settings and verifies an exact fixed outer allowance. | Verify the selected grant/range while retaining isolation, source and output roots. |

Daemon work currently requires 12 GiB available: its separately enforced 8 GiB
ceiling plus 4 GiB headroom. All managed desktop lanes, including root backup
work, serialize through the shared bulk lock. Direct daemon clients and other
services remain outside that lock. See the
[job runbook](../operations/workstation-jobs.md) and
[memory policy](../operations/desktop-memory-management.md).

Read-only live inspection confirmed aggregate effective max/high/swap of
10/8/2 GiB and separate daemon max/high/swap of 8/7/1 GiB. Installed versions
were systemd 262, kernel 7.2.9-xanmod1 and Determinate Nix 3.24.0 reporting
upstream 2.35.3. These observations establish separation, not safe elastic minima.

### The underlying memory controls

`memory.high` induces reclaim and throttling; `memory.max` can cause cgroup OOM.
`memory.min` and `memory.low` protect against reclaim; neither establishes a
viable workload size. Ancestor restrictions remain effective above a child.
Consequently, a percentage limit alone cannot provide adaptive admission.
[Kernel memory interfaces](https://docs.kernel.org/admin-guide/cgroup-v2.html#memory-interface-files).

`MemAvailable` estimates memory available for new applications without swapping.
It is not a reservation. Subtract host headroom and also inspect execution
ancestors; reclaimable host cache does not remove a tighter cgroup restriction.
[Kernel proc documentation](https://docs.kernel.org/filesystems/proc.html#meminfo).

Systemd exposes effective ancestor limits and runtime memory properties.
Percentage limits refer to installed RAM, rather than current available RAM.
Runtime property updates can implement growth but do not resize application
worker pools.
[systemd 262 resource controls](https://github.com/systemd/systemd/blob/v262/man/systemd.resource-control.xml),
[runtime updates](https://github.com/systemd/systemd/blob/v262/man/systemctl.xml).

Do not lower a running hard limit to follow falling availability. Linux v6.18's
`memory_max_write()` can reclaim and invoke OOM after installing a lower maximum;
nonblocking writes defer the work rather than making contraction harmless.
This source example predates the inspected running kernel and demonstrates the
hazard, rather than qualifying every detail of that kernel.
[Kernel implementation](https://github.com/torvalds/linux/blob/v6.18/mm/memcontrol.c).

Systemd-oomd can kill eligible descendants before kernel OOM. Raising a leaf
allowance does not prevent ancestor pressure action. Keep host protection and
collect its outcome separately; SIGKILL alone is not proof of OOM.
[systemd-oomd 262](https://www.freedesktop.org/software/systemd/man/262/systemd-oomd.service.html).

### Waiting, queue slots and recovery

PSI measures time lost to contention and supports threshold notifications.
These signal stalls, not a general transition to enough free RAM. Subscribe
before sampling, then combine pressure/lifecycle notifications with capped,
positive timer backoff to detect recovery after unrelated processes release RAM.
Unprivileged PSI monitors require windows that are multiples of two seconds.
Retain a conservative fallback for hosts without PSI.
[Kernel PSI interface](https://docs.kernel.org/accounting/psi.html).

Pueue 4.0.4 schedules queue/group state, dependencies and slots, without RAM
admission. Parallelism zero means unlimited: pause groups to pause scheduling.
Keep serial executor slots initially. A waiting wrapper may occupy its lane,
provided adapter status clearly says the payload has not started.
[Pueue scheduler](https://github.com/Nukesor/pueue/blob/v4.0.4/pueue/src/daemon/process_handler/spawn.rs).

The adapter currently writes `execution.claim` **before** `_supervise`, including
before admission. Pueue restores running wrappers as killed tasks. Adding a
wait loop improves normal operation but does not make interrupted waiting
automatically resumable. Preserve that conservative behavior initially. Later
recovery needs distinct supervisor ownership and exclusive payload launch claims,
plus proof an old supervisor cannot still launch. Never remove a claim and replay
blindly.
[Adapter claim/recovery code](../../modules/home/services/workstation-jobs-assets/workstation_job.py),
[Pueue restoration](https://github.com/Nukesor/pueue/blob/v4.0.4/pueue/src/daemon/internal_state/state.rs).

### Nix memory and concurrency are separate

`max-jobs` controls concurrent derivations; `cores` supplies `NIX_BUILD_CORES`
to builders, which decide whether to respect it. Neither limits RAM. No supported
RAM-responsive hot-resizing interface was established in the inspected upstream
scheduler paths.
[Nix cores/jobs](https://nix.dev/manual/nix/2.34/advanced-topics/cores-vs-jobs),
[Nix 2.35.4 scheduler](https://github.com/NixOS/nix/blob/2.35.4/src/libstore/build/worker.cc).

Builder environments are established at launch. Daemon-backed Linux builders
derive cgroup placement from the daemon, so raising a client's allowance does
not enlarge their allowance.
[Builder environment](https://github.com/NixOS/nix/blob/2.34.8/src/libstore/unix/build/derivation-builder.cc),
[Linux builder placement](https://github.com/NixOS/nix/blob/2.34.8/src/libstore/unix/build/linux-derivation-builder.cc).

Determinate documents parallel evaluation separately. Upstream Nix source review
does not establish all behavior of the installed fork. Qualify its actual
evaluation and builder paths before changing concurrency.
[Determinate parallel evaluation](https://docs.determinate.systems/determinate-nix/parallel-eval/).

## Implication for this repository

### Request and allocation contract

These fields and flags are **proposed**, not currently available CLI features:

| Contract | Meaning |
| --- | --- |
| Existing `--memory-mib M` | Fixed request: minimum and ceiling equal M. Preserve existing recipe identity and behavior. |
| `--memory-min-mib L --memory-max-mib U` | Opt-in range with a qualified minimum and immutable ceiling. Reject incomplete, inverted or conflicting declarations. |
| Optional preferred allowance | Reporting or latency preference between L and U; never a hidden cap or admission requirement. Add only if callers need it. |
| Admission deadline | Finite wait including lock acquisition. Legacy recipes retain their current timeout semantics. |
| Execution deadline | A versioned interface can separately bound runtime, with an explicit total bound and recorded clocks. |

Do not let `--profile auto` silently reduce required RAM, grant daemon access,
or classify a complete suite as feedback because its lower endpoint fits.
Permanently invalid placement fails before queuing; fluctuating capacity waits.

For a new confined job, conservatively compute the following in bytes:

```text
host_room = max(0, MemAvailable - host_reserve - admission_margin)
ancestor_room = minimum remaining capacity across applicable finite ancestors
grant = round_down(min(request_ceiling, profile_ceiling, host_room, ancestor_room))
admit only if grant >= request_minimum and pressure has remained healthy
```

Include the managed aggregate ancestor; an absent finite ancestor adds no bound.
Keep desktop whole-GiB rounding initially. Recheck under the shared allocation
lock immediately before committing a grant. Missing required capacity data means
wait with a diagnostic, never unlimited admission.

For running work, calculate **additional** capacity and account for already
granted but unused growth. Do not compare an entire enlarged grant with free RAM
or count unused allowances as available for a second allocation. Reserve the
current grant until drainage. A qualified 3–8 GiB request might launch with
5 GiB safely grantable, wait when only 2 GiB is grantable, and grow to 7 GiB
later. Those figures illustrate the contract; they are not measured minima.

Require sustained healthy headroom, distinct reopen/stop thresholds, minimum
intervals and bounded growth steps. Use pressure/reclaim evidence to establish
demand. Persist the intended update, apply it through the owning manager, read
back effective limits and record the outcome. Reconcile incomplete updates
conservatively after crashes. Raise the maximum before the corresponding high
threshold. Falling headroom stops growth and new admissions; it does not shrink
a running hard maximum. Unrelated host growth can still defeat admission estimates.

The current aggregate high threshold can throttle a child below the aggregate
maximum. Initial elasticity stays within reviewed bounds. Using RAM beyond those
bounds needs separate host-wide measurement of interactive applications, VMs,
daemon builders and oomd. Extra host RAM never cancels an ancestor limit.

### Shared-daemon builds need their own path

Implement waiting at the existing daemon guard first. This improves normal
system builds without pretending the daemon belongs to the client. Never convert
a daemon request into confined mode merely to fit a smaller grant.

For builds that must run with smaller viable allowances, extend the existing
`workstation-nix` private-store path first: its builders remain in the allocation.
Preserve sandboxing, compiler settings, immutable source, GC roots and private
output handling. Update exact-budget verification to accept a verified outer
grant/range; an environment variable alone cannot prove isolation or allowance.

Elastic shared-daemon limits need a separate system-owned controller and review
of **all** clients, including those outside the lock. Account for current use,
future permitted growth and client memory without double counting. Prerequisites
include narrow allowlisted controls and proven idle/drain transitions. Do not
add an arbitrary privileged command broker or shrink a busy shared daemon.

### Other execution hosts

Apple exposes memory-pressure change notifications. Use these with conservative
headroom and the existing watchdog. They do not establish an aggregate kernel
ceiling. Retain visible sampling, detached-child and daemon-accounting gaps.
[Apple notifications](https://github.com/apple-oss-distributions/libdispatch/blob/2361ffb78a76f7ee488cd052eb0bc5c767118bf9/dispatch/source.h),
[XNU pressure states](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/doc/vm/memorystatus_notify.md).

Give the small Linux host waiting semantics while retaining its small aggregate
ceiling. Do not advertise desktop compiler capacity or automatically reroute
requests between platforms or hosts.

### Implementation order and acceptance evidence

1. **Wait safely with fixed requests.** Add cancellable, deadline-aware admission
   to native and desktop executors. Preserve lock ordering, serialization and
   interrupted-claim semantics. Expose `waiting-capacity` separately. Holding
   the shared lock while waiting initially causes head-of-line blocking; document
   that trade-off rather than adding concurrent reservations in the first patch.
2. **Version elastic requests and receipts.** Freeze ranges; select and persist
   actual grants. Update typed policy, executor arguments, private-store builder
   and validators together. Retain old recipes. Record bounds, grant, source and
   runtime identity, waiting reasons, clocks, ancestor limits and scope drainage.
3. **Qualify live upward growth.** Keep its controller in the job supervisor.
   Test demand, headroom accounting, hysteresis, update failures and crash
   reconciliation. This stage is needed for more RAM to benefit the same running
   attempt; launch-only selection cannot meet that part of the desired behavior.
4. **Harden resumable prelaunch recovery.** Introduce distinct versioned claims
   only with proof that a prior supervisor cannot launch. Preserve manual pauses
   and ambiguous failures. Redundancy means recoverable records, without duplicate
   payloads. OOM, timeout, interruption and nonzero exits require explicit new
   attempts, never automatic replay.
5. **Qualify workloads and roll out drained artifacts.** Run complete builds at
   proposed minima and normal parallelism; measure growth and reclaim. Use the
   existing scoped package/unit rollout, retaining prior roots and attempts.
   Development requires no production restart or full dirty activation.

Extend the existing
[queue tests](../../tests/workstation/test_workstation_jobs.py),
[admission tests](../../tests/systemd/test_workstation_admission.py),
[bounded executor tests](../../tests/systemd/test_workstation_bounded.py),
[private-store tests](../../tests/systemd/test_workstation_nix.py) and
[fault probes](../../tests/workstation/check_workstation_faults.py). Cover shortage
then recovery, no launch below minimum, every wait's cancellation/deadline,
cross-lane contention, ancestor exhaustion, missing PSI, old recipes, actual
growth, rejected contraction, interrupted updates, claim/launch crash boundaries
and surviving descendants. Verify exit 75 and OOM stay failed without replay,
every acceptance case completes and execution drains. Admission alone is not success.

Keep the first rollout serial. Releasing locks for backfill needs fairness,
starvation prevention and transactional reservations across managed lanes;
it is not a prerequisite for adaptive memory.

## Validation and limits

This investigation read code, primary documentation/source and selected live
unit properties. It ran no builds, stress tests, evaluation, activation or runtime
limit changes. Rumdl 0.2.79 passed for this note and its index; relative links,
whitespace and portable paths passed, and Gitleaks found no leaks in those files.
No new hysteresis value, reserve, growth step, workload minimum or throughput
improvement has been validated.

Older kernel and upstream Nix sources do not establish complete behavior of the
running kernel or installed Determinate fork. Native macOS was researched,
not tested. Existing operational instructions remain authoritative until this
proposal is implemented and qualified.
