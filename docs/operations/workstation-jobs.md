# Durable finite jobs

`workstation-job` adds durable host-local Pueue queues to the native workload
controls. It is selected for the desktop, MacBook and small Linux service host.
SSH chooses the execution host; this is not automatic cross-platform source or
result transfer. The [scheduler research](../research/workload-scheduler-research.md)
compares HyperQueue, Nomad, Slurm, Pueue, GNU Parallel and related tools.

## Submit and observe

Freeze the source and input packet using the owning project's procedure. A source
reference in the receipt records identity; it does not freeze a mutable checkout.
Use an immutable executable or a frozen checkout whose lease remains held for the
job. For example, a finite desktop check with a reviewed 4 GiB working set:

```sh
workstation-job submit --owner CHECK_OWNER --key ATTEMPT_KEY \
  --source IMMUTABLE_SOURCE_REFERENCE --cwd FROZEN_CHECKOUT \
  --profile bounded --memory-mib 4096 --timeout 1200 -- COMMAND ARGUMENTS
workstation-job status JOB_ID
workstation-job log JOB_ID
workstation-job wait --timeout 1200 JOB_ID
```

The opt-in `--profile auto` resolves declared requirements into an immutable
concrete profile before submission. Missing estimates use bounded defaults.
The CLI default remains bounded, preserving existing request identities.
On desktop, an explicit deadline no longer than 120 seconds and a memory request
fitting the feedback profile select feedback; larger or longer confined work
uses bounded. `--requires-daemon` selects a profile whose executor permits daemon access.
On desktop this uses daemon execution with its 14 GiB admission guard; native
macOS uses its single bounded profile and a best-effort client watchdog. An explicit profile overrides auto selection; combining
`--requires-daemon` with a confined profile is rejected. The router does not
inspect shell commands, expand a budget beyond its declared range, or replay a
failed payload. Hosts without feedback keep their single bounded queue.
Use explicit bounded or daemon profiles for complete acceptance suites.

New requests may declare a qualified memory range instead of a fixed size:

```sh
workstation-job submit --owner CHECK_OWNER --key ATTEMPT_KEY \
  --source IMMUTABLE_SOURCE_REFERENCE --profile bounded \
  --memory-min-mib 3072 --memory-max-mib 8192 --timeout 1200 -- COMMAND ARGUMENTS
```

Both endpoints must fit the profile; desktop endpoints must be whole GiB.
Do not combine a range with `--memory-mib`. A range remains bounded under auto
routing and is refused for feedback and desktop shared-daemon execution.
The minimum must cover the complete workload at its normal compiler parallelism;
profile request floors are not evidence that a particular build fits there.
Fixed requests keep their existing identity and size.

New executors wait for temporary capacity shortages within their deadline,
including lock acquisition. Status exposes `memoryAllocation.phase`, selected
`grantMiB`, request bounds and limit-change history. `admission-expired` means
that capacity did not become available before launch; payload failure is separate.
Linux admission checks host reserve and every finite execution ancestor. Healthy
capacity must persist before launch; PSI/lifecycle hints are paired with positive
backoff because PSI has no general memory-recovered notification.

Elastic jobs can grow when demand and healthy spare capacity persist. The owner
raises the hard maximum before the high threshold, reads back the change, and
records it. Granted but unused capacity is not spent twice. Running hard limits
never shrink in response to a snapshot. Pending updates and growth errors stay
visible; growth failure does not replay a payload or undo a possibly applied
increase. Host aggregate ceilings, swap policy and oomd protection still apply.
Mac grants and growth affect the best-effort client watchdog, excluding daemon
builders. Additional RAM does not create additional compiler workers.

Separate daemon-backed dependency preparation from finite confined checks when
the project's source and runtime freeze supports that split. This lets those
checks use their reviewed working-set budget without the daemon's additional
allowance. Existing attempts preserve their original profile and executable.

Run submission on the destination host. Do not wrap SSH waiting in a local heavy
workload lock. Use the host's absolute client path if a noninteractive login does
not load its profile. The returned 32-character ID belongs to the owner/request
key. Repeating the identical request reconciles the same native task. A changed
specification under that key fails. A lost acknowledgment is reconciled by its
stable label; if the outcome remains ambiguous, submission refuses to duplicate
it. Each immutable job also records an exclusive durable execution claim before
launch. Interrupted claimed jobs require a new explicit attempt, never replay.

The adapter preserves argv, cwd and an allowlisted environment. Extra variable
names need explicit `--env NAME`; their values are then persisted privately.
Credentials should normally be read from runtime files or an existing credential
provider. Recipe/result state is private under `$XDG_STATE_HOME/workstation-jobs`
with the normal state-directory fallback. It retains immutable Nix runtime/config
roots, submission acknowledgment, source reference, limits, result and drain
status. Retained roots/results belong to the owning task; retire them only after
explicit completion and required result preservation. No age-based pruning runs.

Native output retention is capped at 16 MiB per adapter execution. Further output
is drained and discarded with a truncation marker. `log` reads only the last 100
lines. Full acceptance artifacts belong in the project's output files and roots;
a truncated console log is not complete evidence. State/history are retained on
disk; they are not active compiler processes.

`wait` is a bounded observer. Its exit 124 means the observer deadline expired and
the durable job is still preserved. A job's own deadline is separate and includes
its executor's queue/admission wait. `cancel JOB_ID` addresses only the matching
stable native identity: queued jobs are stashed with a cancellation receipt;
running jobs receive TERM so their executor can drain its owned scope. It never
calls an empty native kill or a group-wide cancel. Native queue state updates
can lag the cancellation acknowledgment briefly. Before an upgrade, verify the
preserved cancellation is Stashed and unclaimed, or that execution is terminal;
a still-Queued or Running record correctly blocks activation.

## Host execution policy

| Host/profile | Execution and admission |
| --- | --- |
| Desktop `bounded` | Default 4 GiB, reviewed 1–8 GiB whole-GiB requests. Existing bulk/root-backup/feedback locks; fixed or elastic RAM plus 2 GiB host reserve; capacity waiting; cgroup high 90%, hard cap, zero swap, maximum 1800 s. Shared Nix daemon hidden. |
| Desktop `feedback` | Existing 2 GiB hard cap, 1.75 GiB pressure threshold, 256 MiB swap, 120 s ceiling and original feedback admission. Tiny scoped feedback only. |
| Desktop `daemon` | Ordinary `workstation-task`, capacity waiting at the 14 GiB guard and separately accounted Nix daemon budget. Large Nix/system builds remain here. |
| Native macOS `bounded` | One serial queue, default 2 GiB, reviewed 256 MiB–4 GiB requests plus 3 GiB conservative host reserve and normal OS pressure. Process-group watchdog samples every 2 s; 3600 s maximum for explicitly budgeted jobs, with the existing 1200 s default. |
| Small Linux service host `bounded` | One serial queue, default 256 MiB, 64–384 MiB requests, 512 MiB host reserve, 384 MiB aggregate hard cap, zero swap, 1200 s maximum. Read-only store and hidden shared daemon. |

Desktop limits have one typed owner in
[`workload-policy.nix`](../../hosts/nixos/desktop/local/workload-policy.nix).
The system units, runner, queue profiles and private-store helper derive their
ranges, admission headroom and deadlines from it. Invalid reclaim thresholds,
allocation ranges and desktop profiles that exceed executor limits fail evaluation.
`executionMode` declares containment independently of a queue group name;
`allowDaemon` must match the executor’s actual isolation.

The Linux generic module rejects multiple independent groups and requests larger
than its aggregate cap. Desktop groups delegate to the existing shared locks and
ancestor policy. Native Linux jobs use actual cgroup v2 limits; the small host
is not advertised as a large compiler worker. Admission is a snapshot, so the
kernel caps and host headroom remain necessary.

All managed desktop lanes, including feedback and root backup work, acquire the
same exclusive bulk lock before checking admission and retain it until their
owned execution drains. This deliberately serializes managed memory allocations
across Pueue groups; there is no independent per-group reservation budget. A
feedback waiter takes that shared lock before its private feedback lock, avoiding
a cycle with older bounded executors. Active older executions keep their original
locking behavior until they finish.

This is not a global memory reservation ledger for every process on the host.
Direct daemon clients, virtual machines and other services have separate native
budgets and can grow after the snapshot. The queue does not reserve all their
possible remaining growth. Keep their independent caps, actual host headroom and
pressure checks; do not infer whole-host safety from a queue slot. A bounded job
below 14 GiB available can be admitted by its smaller reviewed profile; daemon
builds retain their distinct 14 GiB requirement. New capacity waits use one finite deadline. Admission requires a healthy
interval; growth uses a longer interval and a lower pressure reopen threshold.
These controls reduce oscillation without turning payload failures into retries.
The serial shared lock remains held while a desktop executor waits, so larger
requests can delay smaller requests behind them. Backfill requires a separate
reservation/fairness design.

Native macOS has no equivalent aggregate kernel memory ceiling. The watchdog
accounts only its owned process group and is best effort; it excludes daemon
builders and deliberately detached processes. If output remains held outside the
observed group after cleanup, the receipt reports `drained=false`. Never accept
that as a complete check or silently resume ambiguous descendants. Jobs needing
strict RAM containment require a qualified Linux allocation with adequate real
capacity. A logical scheduler memory request cannot provide that guarantee.

## Nix, compilers and service-owned jobs

Queue slots, derivation concurrency and compiler concurrency are separate controls.
Keep desktop compiler defaults and all required acceptance cases. New native
Mac jobs use one Nix derivation, eight compiler workers and four evaluation
workers. Queue defaults derive from the selected host Nix settings, including
Determinate Nix settings on macOS. Explicit retained compiler environment values
and Nix configuration remain authoritative. New client settings can apply without
restarting an active daemon.
Native Mac receipts explicitly exclude daemon builder RAM from the watchdog.
Desktop daemon policy separately permits one derivation with eight compiler
workers and eight evaluation workers, with a 9 GiB pressure threshold, 10 GiB RAM
ceiling and 1 GiB swap ceiling. Inspect the effective included Nix settings as
well as the native daemon unit; limiting the submitting client's cgroup does not
change daemon concurrency.
On the small Linux host, new Nix requests use one derivation and two compiler
workers. Its separately accounted Nix daemon uses a 384 MiB pressure threshold,
512 MiB hard cap and 128 MiB swap ceiling; confined user jobs still use zero swap.

Linux bounded execution exposes `/nix/store` and `/nix/var/nix` read-only and hides
the daemon socket using Bubblewrap. Missing namespace support fails closed. Use
the [private local-store procedure](desktop-memory-management.md#finite-workloads-with-an-explicit-memory-budget)
for a small confined Nix build, or desktop daemon mode for ordinary realization.
Nix's distributed builders choose actual platform/system features. A remote
builder's memory belongs to that host's enforcement policy, not the SSH client.

Persistent applications stay in systemd/launchd. Existing root backup/build work
keeps its native service budget and shared lock. A finite service-owned user job
can call the same client with a stable owner/request key and then observe its ID;
submission is not a successful service result. Do not queue an infinite daemon,
put a root job into an arbitrary privileged command broker, or migrate active
services just to change schedulers. Temporary task helpers continue to use
`codex-task run` and the task owner's completion procedure.

Codex, Claude Code and OpenCode receive one shared agent instruction source from
this module. Each check keeps one owner and its source freeze. Queue admission,
preparation and CLI build success do not establish product acceptance. Verify
terminal status, expected finite cases, source/runtime identity, accounting and
a drained scope. Payload exit 75, OOM and timeout remain genuine failed attempts;
there is no automatic memory-retry loop or reduction of the daemon guard.

## Restart, updates and recovery

The daemon uses a private Unix socket; no TCP control port is opened. Pueue 4.0.4
is the qualified version. Major state/protocol upgrades require a drained,
reviewed migration and retained backups before updating the version assertion.

Ordinary queued, unclaimed jobs can resume after daemon restart only when their
persisted group was Running and no interrupted or ambiguous execution remains.
Deliberate pauses survive. Interrupted jobs stay failed. If recovery needs an
owner, inspect:

```sh
workstation-job doctor
workstation-job status JOB_ID
workstation-job reconcile JOB_ID --acknowledge-interrupted
workstation-job resume-queued --acknowledge-interrupted
```

Reconcile owned native scopes/process groups before acknowledging. Resume affects
queued work through normal group scheduling; it never force-starts task IDs or
restarts a killed job. Execution claims prevent duplicate payload launch even if
a stale native journal still describes an already claimed job as Queued.

Version-two executions persist a pending-claim marker before spawning payloads.
New clients and workers refuse further admission when an earlier claimed worker
is terminal or missing without proven drainage, including while a legacy
controller remains loaded. A missing receipt is uncertainty, not evidence that
an unrecorded child exited. Legacy claims retain their previous compatibility
rules; upgrading does not retroactively qualify them.

Linux reconciliation requires the matching native terminal identity, no recorded
live worker, an execution-owned kernel stop receipt, and absence of the exact job
cgroup. The proof binds hashes of the claim
and resource receipt. It preserves the interrupted failure and does not rerun
it. A generic Linux preflight that failed before recording a launcher can instead
be explicitly reconciled with `--drain-idle-controller`. This refuses every
unfinished native job, drains the entire idle controller cgroup (including a
child not yet execed), then requires a dead recorded wrapper, two consistent
native absent-unit observations, no matching launcher and an absent exact
cgroup. The controller starts again after the state lock is released.
That proof is labeled `manager-confirmed-absent`, with historical resource values
unknown. Without either Linux proof, investigate with the owner instead of acknowledging
blindly. No automatic repair replays an interrupted check.

Darwin has a separate, explicitly reviewed recovery for a known post-spawn
process group:

```sh
workstation-job reconcile JOB_ID --acknowledge-interrupted \
  --reviewed-darwin-executor REVIEWED_EXECUTOR_SHA256
```

Review the exact immutable executor's `start_new_session=True` ownership contract
before supplying its SHA-256. Recovery requires matching version-two claim and
receipt identities, stable native terminal failure, and two signal-zero absence
observations for both recorded workers and the payload group. A live or reused
ID, permission denial, missing ownership, preflight spawn, or changed input refuses
reconciliation. It stops no process and restarts no controller. The separate proof
preserves the original receipt and failed result; status reports an interrupted
failure with observed group drainage. Historical output EOF and memory peaks
remain unknown. This retains Darwin's best-effort process-group boundary and its
exclusions for detached children and Nix daemon builders. Later unrelated numeric
PID reuse does not invalidate the captured lifetime proof.

Old immutable runtimes retain their original fixed admission and timeout behavior.
New configurations identify allocation policy version one and include admission
in the total worker deadline. Execution claims remain conservative: a controller
crash during capacity waiting still requires owner reconciliation. Only unclaimed
queued work can resume automatically; the new wait does not authorize replay.

Each result records requested memory, queue wait and execution duration, available
memory and pressure at admission, completion reason and available native resource
measurements. Generic Linux service finalizers read `memory.peak`, swap peak,
`memory.events` and pressure before their own cgroup disappears. OOM is a failed
attempt; output EOF or a successful launcher exit alone cannot prove drainage.
Kernels without PSI or peak counters report those measurements as unknown;
optional telemetry cannot prevent recording mandatory stop and drain evidence.
Desktop daemon receipts identify client cgroup enforcement and explicitly exclude
the separately capped shared daemon from the observed client peak. The requested
daemon budget describes the shared daemon ceiling, not an aggregate job peak.

`status` and `doctor` include every unfinished or unresolved job, then up to 100
completed jobs ordered by recipe creation time. Random job IDs never determine
which active work is visible. `historyTruncated` identifies omitted completed
history; `status ID` always addresses its exact job. The `executor` record shows
available/required bytes and the capacity decision before payload admission,
plus native lifecycle transitions as they arrive. A successful capacity snapshot
is distinct from an admitted payload or completed check.
Desktop scope measurements may be unavailable if native unit collection wins the
observation race; missing values remain unknown. Mac peaks are sampled process
group observations with a two-second interval, not kernel high-water marks.

Linux Home Manager uses `X-SwitchMethod=keep-old` so updates do not replace an
active daemon. Its running runtime/config remain explicitly GC-rooted. After
all affected jobs finish, explicitly restart the queue service to adopt the new
unit. Newly created queue-owned desktop scopes bind to the daemon service, so an
unexpected daemon stop drains those scopes. Legacy running scopes are unchanged.

Darwin activation checks the native queue before its write boundary. It refuses
to replace unfinished jobs, then locks new adapter submissions and preserves
original group pause intent across the idle update. A successful LaunchAgent
setup restores only previously Running groups. A failed activation leaves a
visible maintenance record; fix/retry the activation or explicitly reconcile and
resume. A routine activation never stops another task's active workload.

For a scoped rollout, build the exact module's package and generated unit/config,
retain the previous links and roots, and replace only these reviewed artifacts
when the new queue is absent or confirmed drained. The preview profile entry is
`workstation-jobs-preview`; normal Home Manager installation retires it after
installing its managed package. Do not activate unrelated dirty configuration.
Rollback first drains/reconciles the new queue, restores its prior links/package
and reloads the native manager. Never remove its state, recipes or results.

## Verification

Focused reusable behavior tests live in
`tests/workstation/test_workstation_jobs.py`. The native probe is
`tests/workstation/check_workstation_jobs.py CLIENT --state PRIVATE_DIRECTORY`,
with `--profile feedback --memory-mib 2048` for desktop and smaller reviewed
requests on the small Linux host. Submit unit and build checks through
`workstation-job`, which delegates to the native executor. Run the native probe
coordinator outside a workload allocation: it submits and observes its own finite
jobs. Nested durable submissions are rejected to prevent queue deadlocks. These probes exercise literal
argv, filtered secrets, cwd, duplicate requests, failure 75, timeout and actual
Linux memory limits. Additional recovery tests cover stale IDs, activation retry
pause intent, durable execution claims and inherited output pipes.

`tests/workstation/test_workstation_faults.py` covers interrupted supervision,
failed native cleanup and pending-claim recovery. The Linux-only coordinator
`tests/workstation/check_workstation_faults.py CLIENT --base-config CONFIG
--state PRIVATE_DIRECTORY` must run outside an allocation through `codex-task`.
It owns a UUID controller, private Pueue runtime/PID/socket, a 256 MiB aggregate
slice and 64 MiB payloads. It tests manual pause, a multi-child cgroup OOM and
controller SIGKILL without replay, then removes only those disposable units.
The OOM case sets only its private job's pressure threshold to its unchanged
64 MiB ceiling so reclaim throttling cannot consume the finite test deadline.
Record its expected kernel OOM delta and retained failed attempts separately
from production incidents. Never use production daemon restarts for this test.

Native tiny-job passes establish this execution path, not whole-system rebuilds,
large compiler capacity or another project's full acceptance. Preserve failed
pilot receipts and distinguish them from later successful probes. Windows,
existing apps, legacy scopes and active builder guests remain running throughout
a scoped rollout.

### Elastic allocation verification

`tests/workstation/test_workstation_memory.py` exercises ancestor limits, minimum
viability, reserved growth and partial manager updates. Native growth can be
checked with `tests/workstation/check_workstation_memory.py CONTROLLER`: run the
coordinator outside a workload allocation through `codex-task`. It owns a UUID
service under the existing background aggregate, a payload below 64 MiB, and a
64-to-128 MiB grant. It stops only that unit. This is a bounded control-path
probe, not evidence that an arbitrary compiler fits a small allocation.
