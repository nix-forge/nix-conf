# Resource-aware job execution across Linux and macOS

Question: Which scheduler and enforcement arrangement can run finite agent, compiler, and Nix jobs reliably across mixed operating systems while preserving interactive applications, virtual machines, and existing work?

Research date: 2026-10-22. Scope: upstream documentation and source review; measured deployment evidence is recorded separately in the runbook. Pueue behavior is pinned to v4.0.4. Other linked rolling documentation was retrieved on the research date; Nomad documentation identifies v2.0.x, Nix documentation 2.32, and systemd documentation 262. Local package versions must be checked before applying these findings.

## Answer and ranked recommendation

1. Use a durable **Pueue queue on each execution host**, reached over existing SSH, combined with the existing bounded executor. On Linux, enforce a host aggregate workload budget and individual job limits with systemd/cgroup v2. Use native Nix distributed builds for platform-aware realization. Keep long-lived services in systemd or launchd and account for the worker jobs they launch. This is the least disruptive fit for a small mixed-platform workstation fleet; Pueue alone does not supply memory enforcement.
2. Consider **HyperQueue** if multi-host DAGs, arrays, and centralized resource placement become the main workload. Its logical resource requests still require an external enforcement layer; qualify macOS workers rather than assuming that a Linux release binary implies equivalent native macOS production support.
3. Consider **Nomad** when service placement, allocations, and cluster operation justify a privileged control plane. Native macOS execution has different isolation guarantees from Linux. Avoid introducing a cluster manager solely to replace a host-local queue.
4. Use **Slurm** for a dedicated Linux HPC cluster, rather than native MacBook work. Use **GNU Parallel** inside a bounded allocation for fan-out; do not treat its memory options as a transparent durable queue or an application-preserving safeguard.

These are engineering recommendations inferred from the capabilities and constraints below, not claims that installing every scheduler improves reliability.

## Findings and primary evidence

| Tool | Scheduling and persistence | Memory enforcement and platform limits | Operational implication |
| --- | --- | --- | --- |
| Pueue | Persistent local task state/logs, task IDs, dependencies, groups, concurrency, JSON inspection, explicit restart | Supported on Linux/macOS/Windows; documented parallelism is task count, not a host RAM reservation ledger or cgroup limit | Small host-local queue; pair with one authoritative host admission/enforcement layer |
| HyperQueue | Multi-host workers, DAGs/arrays, logical resource matching, optional server journal | Resources are logical; memory requests do not themselves constrain RSS. CPU has special handling | Good scheduler within an already protected worker allocation |
| Nomad | Persistent cluster jobs/allocations, service/batch operation, restart/reschedule policies | Enforcement is driver/OS dependent; isolated exec requires Linux/root/cgroups; raw_exec has no task isolation | More cluster security and lifecycle administration; no uniform native Mac hard cap |
| Slurm | Controller/node batch scheduling and resource selection | Current upstream platform page says macOS unsupported; RAM enforcement requires explicit cgroup/select configuration | Suitable dedicated Linux cluster, disproportionate for a small mixed fleet |
| GNU Parallel | Local/SSH command fan-out, job log and resume modes | No general cgroup containment; memory options may kill/requeue or suspend jobs | Useful subordinate executor only where replay/cancellation semantics are acceptable |

The table is supported by the [Pueue README](https://github.com/Nukesor/pueue), [HyperQueue resources](https://it4innovations.github.io/hyperqueue/stable/jobs/resources/), [Nomad driver reference](https://developer.hashicorp.com/nomad/docs/deploy/task-driver), [Slurm platforms](https://slurm.schedmd.com/platforms.html), and [GNU Parallel manual](https://www.gnu.org/software/parallel/man.html). The following sections identify the details that materially affect a safe configuration.

### Pueue: durable queue, explicit recovery, external enforcement

The [v4.0.4 CLI source](https://github.com/Nukesor/pueue/blob/v4.0.4/pueue/src/client/cli.rs) provides `add --print-task-id`, `--group`, `--after`, `--label`, `--escape`, and JSON inspection. Dependencies require successful predecessors. Labels carry no scheduling or uniqueness logic. `--immediate` bypasses ordinary queue scheduling and should not be exposed by an agent-facing safe wrapper. Prefer an immutable wrapper command or properly escaped arguments; the queue stores a shell command string rather than an argv contract.

The [add client](https://github.com/Nukesor/pueue/blob/v4.0.4/pueue/src/client/commands/add.rs) captures the submitting environment and canonicalizes the working directory on the client. Run remote submission on the destination host, with an allowlisted environment and private state/log permissions. Do not accidentally persist credentials from a general agent environment. The [daemon add handler](https://github.com/Nukesor/pueue/blob/v4.0.4/pueue/src/daemon/network/message_handler/add.rs) creates a new task and saves state before acknowledging it. A connection lost after submission therefore has an ambiguous outcome. A repeated label is not a deduplication transaction: persist an owner request key and reconcile the task ID/JSON state before resubmitting. Exactly-once submission is not established by this API.

The [v4.0.4 restore implementation](https://github.com/Nukesor/pueue/blob/v4.0.4/pueue/src/daemon/internal_state/state.rs#L324) marks tasks previously Running or Paused as Done(Killed), restores Locked tasks as Stashed, and pauses groups with queued tasks. This does not prove every external descendant exited after an abnormal daemon crash. Startup must reconcile old owned process scopes and receipts, identify interrupted work, and explicitly resume reviewed queued work. Do not silently replay a non-idempotent interrupted job. A healthy daemon with a paused recovered queue must be visible as “needs reconciliation,” not mistaken for progress.

Upstream supplies both a [systemd user unit](https://github.com/Nukesor/pueue/blob/v4.0.4/utils/pueued.service) and [macOS LaunchAgent example](https://github.com/Nukesor/pueue/blob/v4.0.4/utils/pueued.plist). Their paths are examples, not Nix store paths; the supplied Linux unit has `Restart=no`. Declare the actual binary/config paths in the platform configuration. Configure recovery policy deliberately instead of assuming a restart resumes tasks. The [configuration wiki](https://github.com/Nukesor/pueue/wiki/Configuration) documents Unix socket, state paths, shell, failure pause, and callback options; validate the installed version's schema rather than copying a rolling example blindly.

The [remote connection documentation](https://github.com/Nukesor/pueue/wiki/Connect-to-remote) supports Unix sockets and TLS with a shared secret. Prefer a private host-local Unix socket and SSH invocation/forwarding. Avoid an unnecessarily exposed control socket. Pueue has MIT/Apache-2.0 licensing. Its [changelog](https://github.com/Nukesor/pueue/blob/main/CHANGELOG.md) documents major-version state/protocol changes: drain jobs, save state, and test migration before upgrading a live queue. Never restart an active daemon as a RAM cleanup technique.

### HyperQueue: resource reservations do not equal kernel limits

The [resource model](https://it4innovations.github.io/hyperqueue/stable/jobs/resources/) matches declared task requests to worker pools, including generic sum resources and automatically detected memory. These resources are explicitly logical; declaring memory prevents the scheduler from assigning more declared memory than the pool contains, but does not impose a process memory ceiling. Bound each worker/job externally and account for the real host reserve.

The [server journal documentation](https://it4innovations.github.io/hyperqueue/latest/deployment/server/) says journal-based recovery restores jobs and allocation state, worker connections must be reestablished, and the last seconds can be lost and recomputed. Stopping a server stops its jobs/workers. These semantics require replay-safe tasks and a drain-first changeover. Preserve completed receipts before journal pruning. The [worker documentation](https://it4innovations.github.io/hyperqueue/latest/deployment/worker/) supports SSH-launched workers; source, runtime, and result transfer remain explicit concerns when there is no shared filesystem.

The [installation guide](https://it4innovations.github.io/hyperqueue/stable/installation/) offers Linux release binaries. A [closed upstream compatibility issue](https://github.com/It4innovations/hyperqueue/issues/690) discusses other platforms, but this is insufficient evidence of equal current production guarantees for native macOS workers. This remains a qualification gap, not a claim that macOS cannot compile it. HyperQueue is [MIT licensed](https://github.com/It4innovations/hyperqueue/blob/main/LICENSE).

### Nomad: useful cluster manager, unequal driver isolation

The [resource specification](https://developer.hashicorp.com/nomad/docs/job-specification/resources) distinguishes memory reservation from hard limit when `memory_max` is used. Driver capabilities determine enforcement. The [exec driver](https://developer.hashicorp.com/nomad/docs/deploy/task-driver/exec) requires Linux, root, and cgroups for isolation; [raw_exec](https://developer.hashicorp.com/nomad/docs/deploy/task-driver/raw_exec) runs with the agent's privileges and no isolation and is disabled by default. Do not describe raw_exec on macOS as equivalent to a Linux cgroup cap.

Set finite [restart/reschedule policies](https://developer.hashicorp.com/nomad/docs/job-specification/reschedule) explicitly: restarting a task on one client differs from replacing an allocation. A compiler check with external side effects must not become an unlimited retry loop. Cluster authentication, privileges, persisted allocations, and upgrades add operational work. Community Edition uses the [Business Source License](https://developer.hashicorp.com/nomad/docs/ce-license-support); review the applicable version's terms before broader deployment.

### Slurm and GNU Parallel

Slurm currently [does not support macOS](https://slurm.schedmd.com/platforms.html). Its [admin guide](https://slurm.schedmd.com/quickstart_admin.html) requires controller/node configuration, consistent identities, synchronized clocks, and authentication. Its [cgroup configuration](https://slurm.schedmd.com/cgroup.conf.html) defaults `ConstrainRAMSpace` off and requires compatible memory resource selection for RAM constraints. An OOM can kill some step members while others remain; final status and drained descendants still require verification. Reserve operating-system memory explicitly. Slurm is GPL-2.0-or-later.

GNU Parallel's [manual](https://www.gnu.org/software/parallel/man.html) documents `--memfree`: it blocks launches below its threshold and may kill the youngest job and requeue it below half that threshold. `--memsuspend` suspends/resumes local jobs. These mechanisms are inappropriate as invisible protection for arbitrary non-idempotent checks. Resume behavior depends on stable command/input order and a matching job log. The [tutorial](https://www.gnu.org/software/parallel/parallel_tutorial.html) distinguishes halt-soon (drain running work) from halt-now (kill running work). Use bounded parallelism inside the owning allocation; retain job logs. GNU Parallel is GPL-3.0-or-later.

## Related services and agent integration

[Task Spooler](https://viric.name/soft/ts/) provides per-user local queues,
controlled concurrency, process context and captured results on Linux and Darwin.
It is a credible small queue alternative; its feature list does not establish
aggregate memory enforcement. Pueue's structured status and explicit persisted
recovery behavior fit this implementation's adapter contract.

[Dask worker memory management](https://distributed.dask.org/en/stable/worker-memory.html)
uses spilling, pausing and nanny termination for Python data workloads.
[Ray's memory monitor](https://docs.ray.io/en/latest/ray-core/scheduling/ray-oom-prevention.html)
can kill workers and retry tasks under pressure. These are application execution
frameworks with their own failure semantics, rather than transparent wrappers
for arbitrary compilers or financial/deployment commands. Use them inside an
accounted allocation when the application already needs that framework.

Native systemd/launchd services remain the lifecycle owners for persistent
applications and timers. Nix's own platform-aware builders remain the realization
engine. Adding several independent general schedulers would create competing
resource ledgers unless they all delegate to one host authority.

The [official Codex workflow guidance](https://developers.openai.com/cookbook/examples/codex/iterating-development-workflows-with-codex)
uses repository instructions and explicit validation criteria to make agent work
repeatable. The local integration applies that principle through one shared
instruction source for Codex, Claude Code and OpenCode: freeze inputs, submit a
stable owner/request key once, retain the ID, observe its terminal receipt, and
verify the original acceptance criteria. This is a local engineering policy,
not a claim that the agent product itself supplies scheduler isolation.

## Integration requirements inferred from the evidence

- Maintain **one aggregate resource authority per host**, covering every queue, Nix builder, and service-owned worker. Separate groups without aggregate accounting can each be safe in isolation while overcommitting the machine together. Admission must be based on requested job class, actual aggregate capacity, host reserve, and pressure; it must not require every job to have the same large free-memory amount.
- On Linux, use hierarchical [systemd resource controls](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html): protect interactive/VM capacity, bound the workload parent, then bound each owned job. A logical reservation is not a substitute for `MemoryMax`/swap controls. Avoid a common fatal OOM group containing the queue and unrelated applications. Use explicit ownership and normal [control-group cancellation](https://www.freedesktop.org/software/systemd/man/latest/systemd.kill.html), rather than broad process-name kills.
- Native macOS lacks Linux cgroup enforcement. Native concurrency/admission and an owned-process-group budget monitor are best-effort protections; do not advertise them as a kernel hard RAM cap. Jobs requiring strict containment belong in a qualified Linux guest/host, whose own memory cost must be accounted for.
- Nix's [native distributed builds](https://nix.dev/manual/nix/2.32/advanced-topics/distributed-builds.html) supply platform-aware placement and SSH builder trust. A daemon-started build can lie outside the submitting client's cgroup. Account/enforce the actual daemon builder scope or use an isolated builder/store; wrapping only `nix build` does not establish whole-build containment. Queue slots, Nix `max-jobs`, and compiler `cores` are different controls. Preserve the configured compiler budget rather than globally forcing one core.
- Record owner/request identity, immutable source/runtime identity, execution platform, CPU/memory/time limits, dependencies, queue ID, output root, and terminal receipt. A queue ID or admission receipt is not a passed check. Terminal verification needs exit status, finite expected case count, source identity, resource accounting, and drained descendants.
- Keep remote waiting outside an exclusive local heavy-work lock. Split local preparation, transfer, remote realization, and result collection. Use stable result roots and bounded retained logs. The existing repository research on build queue efficiency covers this separation.
- Long-lived services remain declared native services. Their finite child work uses the queue or an accounted service allocation. A permanently blocked admission command must not occupy the only execution slot indefinitely. Expose actionable wait reasons, bounded polling, and explicit recovery; avoid duplicate retry storms.

## Validation and limits

This note reviews upstream behavior only. It does not assert that any scheduler was installed, that memory was freed, or that a pending application check passed. Installed versions, generated configuration, destination paths, and native service ownership must be inspected by the implementation owner.

Before deployment, test a disposable queue/scope with tiny jobs: exact argument/environment handling, stable task IDs, lost-acknowledgment reconciliation, failed dependencies, timeout/cancellation and child drain, recovery-paused queues, explicit reviewed resume, bounded logs, aggregate concurrent admission, and source/platform identity. Test crash recovery on the disposable instance only. Transition active work by letting its existing owner finish; do not migrate or restart its processes. Report any untested macOS enforcement or daemon-builder containment honestly.

The implemented configuration and measured native rollout are described in the
[finite job runbook](../operations/workstation-jobs.md). Research capability
claims above are distinct from the limited native probes performed during that
rollout. No full production suite is accepted merely because a queue probe passes.

### Follow-up concurrency and recovery audit

Source inspection found that bounded desktop jobs already retained an exclusive
shared lock, but ordinary bulk and feedback lanes could overlap. The revised
managed lanes share that lock through admission and drainage, including root
backup work. This is deliberate serialization, not a whole-host reservation
ledger: directly launched daemon work and services retain separate native caps.
The desired single aggregate authority remains a system design constraint rather
than a claim that all processes now participate in one reservation transaction.

Recovery also needs evidence for an execution claimed before its first receipt,
and for a launcher started before its PID is persisted. Versioned pending claims
now block uncertain continuation; post-spawn supervision failures reach owned
cleanup. A launcher exit and output EOF do not establish native service drainage.
Disposable Linux tests exercised an actual multi-child cgroup OOM, controller
SIGKILL, deliberate pause preservation and explicit no-replay reconciliation.
These results do not establish a hard macOS memory ceiling or delayed-watchdog
containment during arbitrarily rapid growth.

The [kernel cgroup v2 documentation](https://docs.kernel.org/admin-guide/cgroup-v2.html)
distinguishes memory pressure throttling, the hard ceiling, peak counters and
OOM events. The [systemd resource-control reference](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html)
describes hierarchical limits. The implementation records available native
counters at service stop and keeps missing measurements unknown. A small-host
native rollout exposed a kernel without PSI; optional pressure telemetry must
not prevent otherwise valid bounded work from launching. Expected scoped OOM
test counters and real production incidents require separate retained evidence.
