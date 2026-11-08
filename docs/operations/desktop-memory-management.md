# Desktop memory management

Run memory-intensive development commands as the desktop user through the
explicit workload runner:

```sh
workstation-task nix build --max-jobs 1 .#<TARGET>
workstation-task nix flake check --no-build
workstation-task nix develop --command <COMMAND>
```

Standard `nix` remains unchanged. Heavy local build and check recipes in the
root justfile use the runner. Direct commands, spawned agents, other repositories,
and other checkouts must use it explicitly. Install the desktop home profile to
make the runner available; it refuses work if its matching resource policy is
missing.

For durable submissions and recovery across execution hosts, see the
[finite job queue](workstation-jobs.md). It delegates desktop execution to this
runner and preserves the existing locks, aggregate policy and daemon admission.

## Queue and failure behavior

Ordinary invocations for the desktop user share one bulk lock in
`$XDG_RUNTIME_DIR/workstation-background.lock`. Short, bounded feedback can opt
into a separate single-worker lane with `workstation-task --feedback COMMAND`.
Full builds and complete acceptance suites stay in the bulk lane. A feedback
failure leaves its check failed or pending; resubmit work that exceeds its budget
through bulk rather than omitting the check. The runner preserves arguments,
environment, working directory, stdin, stdout, stderr, and the foreground
command's exit status. Independent callers queue. Nested calls reuse their
existing workload scope after checking the policy.

Each command and its ordinary child processes enter a separate systemd scope
under `background-workload.slice`. The queue stays held until all descendants
exit, including children left in the background. Use ordinary user services for
persistent daemons instead of starting them in this queue. Cancellation with
INT, TERM, or HUP stops only the invocation's scope before releasing its lock.

For a matrix of independent packages, call `workstation-task` separately for
each package and its dependent checks. Run the coordinating loop outside the
runner; nested calls reuse the outer lock. This gives waiting maintenance jobs
an opportunity to run between packages instead of waiting for the full matrix.
Record each command's exit status and retain its output roots so a retry can
reuse completed builds. Run shared integration checks after their dependencies
pass.

After acquiring both bulk locks, admission also requires at least 14 GiB of
available host memory. New runners wait when that snapshot is low or unreadable;
`--admission-timeout` bounds lock and capacity waits, with exit124 on expiry
before launch. Older immutable runners retain their exit75 behavior. Admission
is a snapshot, not a memory reservation. Aggregate limits and application containment remain
necessary after admission. The floor allows for the separate 10 GiB Nix daemon
budget plus 4 GiB of headroom. A 4 GiB floor still allowed a global OOM during
parallel compilation with an active desktop. When the floor cannot be met,
defer the build or use a suitable native remote builder; do not bypass the guard
or stop unrelated applications to obtain a passing check.

After the foreground command exits, the runner blocks on the scope's
`cgroup.events` notifications until its descendants finish. It does not repeatedly
query systemd. See the [kernel's populated notification contract](https://docs.kernel.org/admin-guide/cgroup-v2.html#un-populated-notification).
SIGKILL cannot run cleanup; aggregate cgroup limits still apply to surviving
work, which must be inspected before starting another heavy task.

### Bounded feedback

Feedback scopes keep the same aggregate ancestor policy and add a 1.75 GiB
memory pressure threshold, 2 GiB hard limit, 256 MiB swap limit, one CPU of quota,
256 tasks and a two-minute lifetime. Managed feedback and bulk jobs serialize
through their shared execution lock. Nested calls
inherit their outer scope and budgets. Existing bulk invocations retain their
original lock and resource behavior.

Admission requires at least 3 GiB available host memory and 2 GiB current
headroom under the aggregate hard limit. Insufficient headroom exits75 before
executing the command. These are admission snapshots, not physical reservations;
aggregate pressure policy and hard limits remain authoritative. Scope expiry,
OOM, failed launch and cancellation remain failures. Feedback is suitable for
scoped static checks and a small selected browser workflow, not daemons, broad
builds or whole-suite acceptance. A small Nix output can still require evaluating
the complete host or home configuration: keep that evaluation in the bulk lane,
including isolated generated-policy targets. Output size alone does not establish
feedback suitability. Keep Nix compiler parallelism unchanged.
An expired or OOM-killed descendant fails the invocation even when its foreground
command already exited successfully.

### Finite workloads with an explicit memory budget

Use `workstation-task --bounded-memory 4 COMMAND` for finite host processes
whose complete working set fits a reviewed 4 GiB budget. Budgets from 1 through
8 GiB are accepted. Admission requires that budget plus 2 GiB of available host
RAM and sufficient remaining space under the aggregate workload ceiling. A
4 GiB compiler check therefore requires 6 GiB available; an 8 GiB request requires
10 GiB available. The ordinary bulk mode retains its separate 14 GiB admission
floor for the shared Nix daemon. Temporary shortages now wait; use
`--admission-timeout SECONDS` to bound direct runner lock and capacity waits
(default 1800 seconds).

Use `workstation-task --memory-min-mib 3072 --memory-max-mib 8192 COMMAND` for an
explicitly qualified elastic request. Both endpoints are whole GiB. The runner
selects current capacity above the minimum and can grow its allowance within the
ceiling when demand and spare capacity remain healthy. It retains the same
namespace, aggregate and swap controls; it never shrinks a running hard limit.
The [finite job guide](workstation-jobs.md) describes receipts and deadlines.

This profile enforces its own RAM ceiling, a pressure threshold at nine tenths
of that ceiling, zero swap, and a 30-minute deadline. It retains configured CPU
parallelism. It holds both the bulk and feedback locks, waiting for existing
work to finish normally. Descendants drain before either lock is released;
expired or OOM-killed work remains failed. Admission is still a snapshot, not a
physical reservation against later allocations by other applications.

Nix daemon builders run outside a user workload scope. To prevent ordinary
commands from escaping the smaller budget through that daemon, this profile
uses Bubblewrap to hide the local daemon socket and expose the store and its
database read-only. Missing namespace support fails the invocation; it never
falls back to an unconfined command. Ordinary daemon-backed builds and commands
that need store writes continue to use the bulk mode and its existing guard.
Read-only Nix evaluation can use the explicit local-store mode:

```sh
workstation-task --bounded-memory 4 nix \
  --extra-experimental-features read-only-local-store \
  eval --store 'local?read-only=true' --expr '1 + 1'
```

The [Nix local-store documentation](https://releases.nixos.org/nix/nix-2.32.1/manual/store/types/local-store.html)
explains its read-only database mode. Existing required source, runtime and
acceptance checks remain mandatory; a task owner must review compatibility
before moving a saved check packet into this profile. Choose its budget on the
outermost invocation. Nested ordinary calls inherit that scope and isolation.
Like the ordinary queue, this is cooperative workload containment: a command
that explicitly launches unrelated system services or remote jobs needs its own
reviewed resource accounting and must not claim this scope contains that work.

Small native Nix builds can also run inside this profile using an explicit
private local store, such as `--store "local?root=$HOME/.local/state/<TASK>/nix"`,
with `--option build-users-group '' --option builders ''`. Unlike the shared
daemon, that local builder inherits the command's RAM cap. Seed only its needed
dependencies using `nix copy --from 'local?read-only=true' --to <PRIVATE_STORE>`
with the read-only feature above, or let it fetch required inputs into that
private store. Keep sandboxing enabled. Outputs remain in the private store;
this does not install them into the system store or qualify a system deployment.
Retain required output roots and receipts until the owning task is complete.
The native integration probe builds and checks a real tiny derivation through
this route in a disposable store under a 1 GiB scope.

The desktop's `workstation-nix` command packages the private-store route for
finite package builds and checks:

```sh
workstation-nix --memory-gib 4 \
  --state "$HOME/.local/state/workstation-builds/package-check" \
  --file ./frozen-package.nix
```

It enters the bounded runner before evaluation, uses a writable private store,
retains sandboxing and configured compiler parallelism, and disables remote
builders. A 4 GiB request needs 6 GiB available instead of the shared daemon's
14 GiB floor. Installables such as `.#packages.x86_64-linux.<PACKAGE>` can replace
`--file`. Freeze mutable sources before durable submission as described in
[the job guide](workstation-jobs.md); the helper does not freeze a checkout.

Reuse the same task-owned state directory to reuse cached dependencies. Each
attempt retains its own output roots and receipt, including the derivation
identity, exit status, and usable physical output paths under the private store.
Outputs are not installed into the system store or activated. The job receipt
remains authoritative for allocation enforcement and drained execution. A failed
build is not retried automatically. The helper can run inside a bounded
`workstation-job` allocation when `--memory-gib` matches that outer allocation;
it refuses an incompatible outer scope instead of silently changing its budget.
For a qualified elastic build use `--memory-min-gib L --memory-max-gib U` instead
of `--memory-gib`. Inside an elastic queue allocation, pass the same range; the
helper verifies actual cgroup bounds, zero swap and daemon/store isolation before
using that allocation. Its receipt records the range and initial actual maximum.
Shared-daemon and full desktop builds retain their own path.

Use this route when the complete evaluation and build fit the selected budget.
It does not make a large system closure fit a small allocation. Desktop system
builds retain their declared host placement and daemon policy. The native
`tests/systemd/check_workstation_nix.py HELPER --state PRIVATE_DIRECTORY` probe
builds a real dependency, checks its output, verifies a retained GC root, and
requires a deliberately failing package to remain a failed attempt.

The pressure thresholds leave room for useful working sets before reclaim:
feedback retains 256 MiB between its high threshold and hard ceiling, and bounded
jobs retain ten percent. Hard ceilings, zero bounded swap, deadlines, aggregate
limits and host admission reserves still apply. A timeout or OOM remains a
failed attempt; raising a threshold does not qualify a larger working set.

`workstation-task --status` reads private lifecycle records in the runtime
directory. Each new invocation records queued, admitted, foreground-completed
and scope-completed times with monotonic timestamps. Capacity checks retain
available and required host bytes, the concrete profile, optional aggregate
headroom and the reason for refusal even when no payload was admitted.
Unreadable counters remain unknown and fail admission. Admission delay includes
small bookkeeping overhead around lock acquisition. Foreground completion stays
separate from waiting for remaining descendants. Records contain scope identity
and lane, not command arguments or environment values. Unfinished records after
a forced supervisor kill need inspection; they do not prove the scope is active.
The ordinary default queue requires the updated package to produce these records.

The queue is per user on one host. It does not serialize root jobs or remote
builders. Run remote development commands through the desktop user's runner on
the desktop. A local `workstation-task deploy ...` does not wrap a remote Nix
client. The daemon's separate budget still applies to its builders. Programs
that explicitly start services or new scopes can leave the runner's group;
this policy controls cooperative development work, not hostile code.

An SSH client that only waits for work on another host should stay outside the
local workload queue. Apply that host's scheduling policy to the remote payload,
and retain task ownership of both the client and any remote helpers. Queue heavy
local preparation, compilation, or evaluation as separate finite steps. A remote
build wait must not occupy the local bulk lane for its entire lifetime.

## Native remote package builds

Do not hold the desktop queue while waiting for compilation or runtime checks
on another host. Queue local evaluation and transfers separately, then run the
native realization directly on that host. A client using `--max-jobs 0` still
occupies the queue when the whole client is wrapped; it is not a placement fix.

For an existing derivation, use:

```sh
just remote-realise <SSH_HOST> /nix/store/<PACKAGE>.drv /absolute/remote/result 8
```

The command rejects desktop system closures, which use the dedicated desktop
build recipes. It checks that the derivation's platform matches the remote host,
queues local derivation inspection and copying, and then releases the desktop
queue during the SSH build. The remote build uses one derivation, the requested
compiler count, no secondary builders, and no advertised emulated platforms.
It retains the output root on the remote host and prints the verified store
output paths for build receipts. It does not copy the result back;
consumers that need a local result must copy it separately through the queue.
Instantiate and root the derivation under `workstation-task` before calling this
command, for example with `nix-instantiate --add-root <ROOT> --indirect`.
Keep coordinators outside the runner, including this command itself, or an outer
workload lock would remain held throughout the remote wait. The command rejects
that nested usage before contacting the remote host. Existing local output
roots and active builds remain owned by their original tasks.
See the [remote queue research](../research/build-queue-efficiency-research.md#remote-waits-and-queue-placement).

## Immutable package jobs

Use `just linux-build TARGET PACKAGE [REPOSITORY]` for project packages. Before
waiting, it stores and roots immutable copies of the launcher and selector.
After admission to the workload scope, it archives the Git-filtered flake and its
inputs once, roots those sources, and builds from that snapshot. It retains
output roots and a private JSON record under
`$XDG_STATE_HOME/nix-conf/builds`, falling back to `$HOME/.local/state`.
This permits reuse of completed builds without keeping the queue occupied for a
whole matrix. Do not edit a submitted launcher or its external helper inputs.

The recorded source is the snapshot taken when the task acquires the queue;
it is not a promise that a mutable checkout is frozen at submission time.
The job records selected platforms, compiler concurrency, source and output
paths, phase, exit status, approximate queue waiting time and execution duration. Cancellation belongs to `workstation-task`
and its scope. Use retained outputs when retrying, and retire their roots only
after the owning task is explicitly complete. Do not remove roots by age.

The desktop's declared compiler default is eight jobs, with one derivation at a
time and the existing memory ceiling. Use that configured parallel compiler
budget for normal builds. This is a throughput policy informed by the
completed package work, not a CPU reservation or a guarantee of full utilization.
The live daemon setting also uses eight jobs. The shared Linux source launcher
reads the host compiler setting after queue admission, so lower host settings
remain effective. Automatic settings use at most eight jobs and three quarters
of the available logical CPUs. Explicit command flags win. Existing builds keep
the count chosen when they started; changing that count requires a new build.
See the [hardware utilization research](../research/build-hardware-utilization-research.md).

### Compiler pressure recovery

When compilation slows, compare interval deltas in the builder's `cpu.stat`,
`memory.events`, and `memory.pressure` with its memory and swap limits and the
host's available memory. Compiler processes consuming CPU can be spending that
time in kernel reclaim. Useful compilation requires user CPU progress without
sustained memory or I/O stalls.

Keep the configured compiler budget while resolving the limiting resource.
Review the working set and interactive headroom with the owner of the host
memory policy before changing its allowance. Use a suitable native remote
builder when the local host cannot accommodate the parallel build. A budget
change must be applied to the live builder before retrying; an edited Nix file
alone does not alter a running daemon's limits. Report the capacity constraint
when neither placement nor a safe allowance is available. Forcing one compiler
job is an explicitly requested execution mode. Reclaim recovery follows the
resource budget and placement procedure above.

Preserve completed outputs and immutable source records. Let useful compilation
finish; changing an active build's compiler count requires restarting it and
discards unexported intermediates. Before interrupting a stalled attempt,
coordinate dependent queue entries so another caller cannot restart the same
derivation with the unresolved resource mismatch. Give each package and its
checks a queue turn, then release the queue for other work.

## Resource policy

Desktop workload budgets are declared once in
[`workload-policy.nix`](../../hosts/nixos/desktop/local/workload-policy.nix).
System cgroups, queue profiles, runner admission and private-store CLI bounds
derive from this typed policy. Its JSON is included in the generated memory
policy output. Keep reviewed host ceilings stable across free-memory snapshots;
elastic per-job grants can grow within those ceilings. The typed admission policy
owns wait defaults, healthy intervals, pressure thresholds and growth steps.
Use receipts and pressure evidence to qualify workload ranges or host changes.

The [host memory module](../../hosts/nixos/desktop/local/memory.nix) owns the budgets.
It protects session and interactive application memory through the required
ancestors. These are best-effort reclaim protections, not reserved physical RAM
or immunity from the kernel OOM killer. Compressed swap and the kernel also need
physical memory.

Background jobs share an aggregate slowdown threshold, hard memory ceiling, and
swap ceiling. They have lower CPU and I/O weights. `systemd-oomd` monitors only
the background workload subtree and can terminate an entire task under sustained
pressure. A confined kernel OOM likewise terminates that task as a group.
Interactive application scopes retain their child-OOM survival policy.

The desktop has an additional 8 GiB disk-swap fallback on its encrypted root,
at disk-swap priority, below compressed swap. It provides space for cold interactive pages
when compressed swap and the primary disk swap are full. This does not raise
RAM ceilings or compiler parallelism. Keep an active swap file while its pages
are needed; removing it requires a separate capacity review and safe drain.

The Nix daemon has a 9 GiB pressure threshold, 10 GiB hard memory ceiling and
1 GiB swap ceiling. Eight parallel Node/V8 compiler workers stopped making user
CPU progress under the former 7/8 GiB RAM limits while the swap allowance was
full and the host still had available RAM. The larger reviewed working set keeps
the configured compiler count and swap ceiling. Shared-daemon admission derives
from this 10 GiB ceiling plus 4 GiB of host headroom, requiring 14 GiB available.
The updated Node packages also use a scoped Clang toolchain: raising the RAM
allowance alone did not resolve GCC's reclaim stall. This allowance does not
establish capacity for every native build.

The Nix daemon also has a `CPUQuota=1120%` ceiling on this 16-thread desktop,
equivalent to 70% of its logical CPU capacity. Compiler job limits alone do not
constrain worker pools created by tests. The daemon quota includes its build
descendants; it does not limit user-side evaluation or reserve physical cores.
Lower scheduling weights continue to favor interactive work under contention.
Systemd expresses [CPU quotas as a percentage of one CPU](https://github.com/systemd/systemd/blob/v261.2/man/systemd.resource-control.xml),
so this value must be reviewed if the host's CPU topology changes.

The desktop keeps `/tmp` on the root filesystem rather than tmpfs because its
development scratch data previously consumed most of the available tmpfs and
was therefore memory- and swap-backed. `/tmp` is cleaned at boot. The Chromium
application family also has a separate 10 GiB pressure threshold, 12 GiB hard
memory ceiling, and 8 GiB swap ceiling. The swap allowance lets cold agent and
tool memory spill to disk after zram fills instead of pinning it in RAM while
host swap remains available. These limits contain retained browser workers
without changing the replaceable-workload budget. Codex uses the
application-specific aggregate policy described below.

The Zen browser family has an 8 GiB pressure threshold, 12 GiB hard memory
ceiling and 8 GiB swap ceiling. An earlier 4 GiB swap ceiling coincided with
a global OOM below its former 12 GiB pressure threshold while disk swap was
still available. Earlier reclaim and more swap headroom reduce that overcommit;
they do not guarantee that the host cannot exhaust memory. Browser scope
drop-ins apply to each matching application scope, rather than one aggregate
budget across every separately launched browser instance.
The kernel stops swapping a cgroup's anonymous pages once it reaches its
swap ceiling, even when the host has free swap.
[Kernel memory and swap controls](https://docs.kernel.org/admin-guide/cgroup-v2.html#memory-interface-files).

REA is installed with its skill but has no automatic MCP registration. Agents
use its one-shot CLI, whose process exits after each operation. Work that needs
a persistent MCP session owns its transport and shuts it down when finished or
paused; it must preserve required Evidence before closing that session.
Both workstation hosts also set REA disabled in Codex's managed startup defaults,
so a stale saved user setting does not enable it at client startup. These are
startup defaults; they do not restrict other MCP servers or change approvals.
See [Codex managed configuration](https://learn.chatgpt.com/docs/enterprise/managed-configuration).

Inspect the actual settings and pressure with:

```sh
oomctl dump
systemctl --user show background-workload.slice session.slice app.slice
cat /proc/pressure/memory
free -h
swapon --show
```

Zram keeps a bounded logical capacity without a smaller resident cap. A resident
cap can fail swap writes before the logical device fills; it is not a reliable
spill threshold for disk swap. See the [kernel zram documentation](https://docs.kernel.org/admin-guide/blockdev/zram.html)
and [resource-control documentation](https://github.com/systemd/systemd/blob/v261.2/man/systemd.resource-control.xml).

## Persistence and recovery

Runtime settings are separate from NixOS and Home Manager activation. Disko's
swap partition receives a fresh random encryption key each boot, so hibernation
is disabled. Core dumps are bounded and stored on encrypted root.

Home Manager preserves regular-file conflicts in private unique
backup directories; an activation step also handles the foreign Hyprland symlink
that its normal backup hook does not handle. Dry runs preserve the original files.

## Validation

The runner is also available as a standalone package, using the same host-owned
resource settings. Build and test it before installing it into the current
user's Nix profile:

```sh
workstation-task nix build .#workstation-task -o result-workstation-task
bash tests/systemd/check-workstation-feedback.sh result-workstation-task/bin/workstation-task
nix profile install "$(readlink -f result-workstation-task)"
type -a workstation-task
workstation-task --help
```

Installing this package updates the user command without a whole-system switch;
it does not activate a changed resource policy. Existing commands keep their
running scopes. The runner refuses commands when the active aggregate policy
does not match its built settings. A profile-installed preview can shadow the
Home Manager version: remove that specific profile entry when returning ownership
to Home Manager, after checking `nix profile list`. Keep other profile entries.
Do not use a complete profile rollback if unrelated installations followed it.
Normal Home Manager activation retires the `workstation-task` and
`workstation-task-preview` profile bridges after installing its managed command.

Build the generated policy without building unrelated desktop applications:

```sh
workstation-task nix build --no-link --print-out-paths \
  .#nixosConfigurations.desktop.config.system.build.desktopMemoryPolicy
```

The isolated VM check runs the generated runner and policy in a separate user
manager. It exercises queue ownership, cancellation, descendant exit and confined
OOM handling without sharing the host's active queue:

```sh
workstation-task nix build --no-link .#checks.x86_64-linux.desktop-workload
```

Run the live integration probe outside the workload runner so it can test
independent queue callers. It requires `strace` to detect repeated status probes
and cgroup waits that spin instead of blocking:

```sh
bash tests/systemd/check-workstation-task.sh <POLICY_STORE_PATH>
python3 tests/systemd/check_chatgpt_oom.py
```

The OOM probes allocate only within disposable 96 MiB groups. They do not test
whole-machine exhaustion or prove that applications recover after losing an
essential child process.

The focused native lane probe can run against the built runner without waiting
for unrelated bulk work:

```sh
bash tests/systemd/check-workstation-feedback.sh <RUNNER_STORE_PATH>/bin/workstation-task
```

It checks actual scope caps, feedback serialization, nesting, cancellation,
descendant drain, private admission timing, cross-lane progress and refusal before
execution when capacity is insufficient. The existing full integration probe
remains required for default bulk and OOM behavior. Disposable fixtures change
only queue names or shorten the rendered scope lifetime from 120s to 1s to exercise
expiry without a two-minute test. Keep those fixtures out of installed policy.

## Codex desktop and temporary tools

The desktop home profile packages a Codex launcher under a shared
`app-codex.slice`: 16 GiB `MemoryHigh`, 18 GiB `MemoryMax`, and 22 GiB
`MemorySwapMax`. A 14 GiB high-threshold trial produced UI reclaim stalls during
active tool/cache bursts despite host headroom; the current threshold follows a
live comparison in the [resource audit](../research/desktop-resource-efficiency-research.md#later-freeze-investigation-reclaim-threshold-calibration).
These are containment settings, not reserved RAM or a throughput claim. `MemoryHigh` can introduce reclaim stalls, and hitting `MemoryMax` can
terminate application processes. Review measured pressure before tightening them.

Earlier 10 GiB and 18 GiB swap allowances constrained cold application pages
while encrypted disk swap remained free. The 22 GiB allowance retains the RAM
ceiling; it does not allocate swap or reserve physical memory. Validation moved
cold pages in measured batches while preserving at least 4 GiB of free host
swap and the then-configured 12 GiB bulk admission floor. Keep host swap headroom for other
workloads.
For deliberate recovery, the kernel's scoped `memory.reclaim` interface can
move cold anonymous pages in small measured batches without terminating an
application. Stop on poor reclaim yield, new OOM events, or inadequate remaining
swap; monitor application responsiveness and preserve active workload state.
See [proactive reclaim](https://docs.kernel.org/admin-guide/cgroup-v2.html#memory-interface-files).

Chromium creates its own scope after launch. The wrapper gates application exec
until a PID-specific runtime drop-in places that scope in the same slice as the
renderer. The exact drop-in supersedes the generic Chromium limits only for
that invocation; other Chromium applications retain their existing policy.
Systemd owns cleanup after a launcher failure, including SIGKILL, and binds the
moved application scope to its launcher service. Arguments and ordinary caller
environment variables and file-creation mask are preserved; service-manager
metadata is regenerated and the per-launch state directory remains private.
The `chatgpt` desktop launch command and desktop entry both use this launcher.

The new placement applies to a fresh Codex process. Opening another window while
an older singleton is running does not move its existing allocations. Finish
active work and exit normally before testing a fresh launch; configuration
activation does not force an application restart. Verify both renderer and
backend membership through `/proc/<PID>/cgroup`, rather than inferring placement
from their process ancestry.

A scoped rollout can install the Nix-packaged launcher and task helper as
`codex-resource-preview` in the user's Nix profile while linking only the
resource policy, timer, desktop entry and task instructions. This avoids
activating unrelated pending configuration changes. The next normal home
activation removes that temporary profile package after installing its managed
packages, preventing the preview from pinning an older application version.

A swap-only rollout can use `workstation-swap-preview` to keep its unit in the
Nix store while preserving the running RAM thresholds and applications. Its
managed activation retires that profile entry only after `linkGeneration` and
after verifying the installed unit resolves to the new generation's unit.
Failed, missing, or unexpected links keep the preview root for recovery.

Compiler defaults are not a universal worker limit. A build backend may launch
more workers than `NIX_BUILD_CORES`; inspect its actual command and worker count
when the daemon has high reclaim pressure despite available host RAM. For
example, [meson-python](https://mesonbuild.com/meson-python/how-to-guides/meson-args.html)
accepts explicit Ninja job arguments through `compile-args`. Keep the daemon's
memory containment while diagnosing such a backend; raising its RAM ceiling
can shift the failure to the whole desktop.

`codex-pressure.timer` samples every 30 seconds during the graphical session.
Two consecutive samples with at least 5% one-minute full memory pressure, or
Codex near its hard memory limit, can notify. Near-exhausted swap also requires
high resident usage; cold swap occupancy alone is quiet. Notifications share a
15-minute cooldown per warning type. The monitor never kills processes or
changes limits. Its private latest snapshot is
`$XDG_STATE_HOME/codex-resources/pressure.json`, using the normal state-directory
fallback when that variable is unset. Diagnostics also observe the Nix daemon
and queued-workload groups independently. Samples include partial/full memory
pressure, actual local limits, available host RAM, and separate hierarchical and
local memory-event deltas, plus separate swap-limit and swap-allocation failure
counters and deltas. Swap-limit failures can occur without new RAM-limit events.
Do not add parent counters to their descendants.
Missing groups remain explicitly unavailable; recreated groups, reboots, counter
resets and long sample gaps start a new delta baseline.

Private `pressure-history.jsonl` and `pressure-history.jsonl.1` in that directory
retain at most 1 MiB each. Samples append without rewriting the whole history;
retention time depends on record size. Warnings retain their original thresholds
and cooldowns and name concurrently stalled monitored groups. This provides
context, not proof of which workload caused host pressure. Compare an affected
group's new high-limit events and PSI with host headroom before changing limits.
The monitor records no process arguments, environment or conversation contents.

Temporary commands with descendants can use:

```sh
codex-task run COMMAND ARGUMENTS...
codex-task list
codex-task finish
```

The helper requires the calling Codex thread's `CODEX_THREAD_ID`. Its service
cleans remaining children when the main command exits, and foreground
cancellation stops that invocation's service. `finish` stops only
services registered to that thread, so call it after the owning task is complete.
Persistent applications belong in declared user services. Keep heavy work in
`workstation-task`; the task helper does not replace the workload queue. Native REPL kernels
and MCP transports retain their own close/reset APIs: the global Codex context
requires their task owner to save results and release them at completion. This
is cooperative cleanup, not an age-based process reaper or a transcript parser.
It preserves state needed by active work and follow-up requests.

Build the isolated policy and helper artifacts:

```sh
workstation-task nix build --no-link --print-out-paths \
  '.#nixosConfigurations.desktop.config.home-manager.users.<USER>.xdg.dataFile."codex-resources/policy".source'
```

Substitute the configured login name for `<USER>`. The resulting policy directory
contains the slice, monitor units, generic launch helper, task helper and generated
monitor config. It does not rebuild the GUI application or its backend; the
configured desktop package is built with the normal home/system activation.
Run the focused behavior check and disposable integration probe through the
workload queue:

```sh
workstation-task nix build --no-link .#checks.x86_64-linux.codex-resources
workstation-task python3 tests/systemd/check_codex_resources.py <POLICY_STORE_PATH>
```

It models Chromium's independent D-Bus scope request, verifies both process groups
share the slice, preserves literal URL arguments and caller environment, kills
only its disposable launcher to check abrupt-failure cleanup, and verifies that
one task owner cannot clean another owner's service. It opens no Codex window
and performs no memory-exhaustion test. Full desktop interaction after the next
normal application restart remains a separate runtime check.
