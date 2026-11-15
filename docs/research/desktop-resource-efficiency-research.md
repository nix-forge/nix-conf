# Desktop memory and resource efficiency audit

Reviewed: 2026-10-16. Scope: the desktop host and home profile, Linux
7.2.9-xanmod1, systemd 261.3, and effective cgroup-v2 policy. Repository HEAD:
`21237bdb8974bda44d4a8c591b50e542dd7dc6c3`. Existing working changes were part
of the inspected configuration; this audit did not change runtime policy.

## Answer

Preserve the existing build queue, compressed swap, ancestor memory protection,
and I/O controls. The clearest containment gap is that the desktop agent's
renderer and backend occupy separate scopes, and only the backend scope has
memory limits. Correct grouping and task-owned session cleanup offer a more
targeted improvement than tightening every application's limits.

Add pressure visibility before global tuning. A low live swappiness value
warrants a controlled comparison, but no measured performance gain or safe
aggregate application ceiling was established in this audit.

## Findings and sources

### Effective safeguards already present

- The Nix daemon has a 7 GiB pressure threshold, 8 GiB memory ceiling, 1 GiB
  swap ceiling, and CPU quota equivalent to 11.2 logical CPUs. Its current
  cgroup recorded no high-limit or OOM events. The source sets one
  derivation, cores=8 and eval-cores=8; individual tools and client overrides
  can change effective concurrency.
- Queued development work has an aggregate 8/10 GiB memory policy and 2 GiB
  swap allowance, lower scheduling weights, and scoped oomd monitoring.
- Session/application memory protection is present, including the 6 GiB
  allowance at each required system ancestor. These are reclaim preferences,
  not preallocated RAM or OOM immunity.
- Both NVMe devices have enabled iocost controllers with automatic models.
  Thus the configured I/O weights have an active enforcement mechanism.
- Zstd zram has about 15 GiB logical capacity and higher priority than the
  16 GiB disk swap. One sample stored about 12 GiB of original data in about
  3.8 GiB of allocated RAM. Compression consumes RAM as well as saving it.
- The active CPU profile is balanced, with amd-pstate-epp and
  balance_performance preference. A powersave governor label alone does not
  establish poor interactive performance. No CPU comparison was performed.
  [Kernel AMD P-State documentation](https://docs.kernel.org/admin-guide/pm/amd-pstate.html).

Policy owners: [host memory](../../hosts/nixos/desktop/local/memory.nix),
[build policy](../../hosts/nixos/desktop/local/system.nix),
[I/O control](../../hosts/nixos/desktop/local/iocost.nix), and
[hardware](../../hosts/nixos/desktop/local/hardware/platform.nix).
The kernel documents [memory and I/O controls](https://docs.kernel.org/admin-guide/cgroup-v2.html)
and [zram accounting](https://docs.kernel.org/admin-guide/blockdev/zram.html).
This audit supersedes the older desktop review's observation of missing iocost;
it does not imply the old observation was incorrect at its review date.

### Priority 1: contain the complete application at launch

The desktop agent's backend was in a Chromium-named scope with 10 GiB high,
12 GiB max and 8 GiB swap. Its renderer was in the separate UWSM ChatGPT scope,
with all three controls unlimited. The latter held about 4.8 GiB memory and
1.2 GiB swap in one sample. The policy is explicit in
[interactive desktop configuration](../../homes/desktop/local/interactive-desktop.nix).
The generic Chromium prefix also matches a Spotify scope: it is not an
application-specific aggregate budget.

Investigate an application-specific parent slice covering both launch paths.
Verify actual renderer, backend, helper and tool membership after launch,
including children that request new systemd scopes. Merely wrapping the initial
command or copying 12 GiB ceilings onto both scopes does not establish a shared
12 GiB budget. Keep the existing survival policy during the investigation.

Start with accounting and representative working-set measurements. Trial a
pressure threshold before choosing a hard aggregate ceiling; copying the current
backend ceiling to the whole application could terminate legitimate active work.
MemoryHigh throttles and can itself introduce lag; MemoryMax is a final defense.
Moving a running process also leaves existing memory charges with their original
group, so validate placement from a fresh launch.
[Kernel memory ownership](https://docs.kernel.org/admin-guide/cgroup-v2.html#memory-ownership),
[systemd resource controls](https://github.com/systemd/systemd/blob/v261.3/man/systemd.resource-control.xml).

### Priority 2: observe pressure and bind tools to task lifetime

Collect per-application memory, swap, PSI and event deltas, with rate-limited
notifications only when pressure persists or limits are approached. High swap
occupancy alone is not evidence of current thrashing. At the end of this audit,
memory avg10 pressure was zero, despite substantial occupied swap.
[Kernel PSI](https://docs.kernel.org/accounting/psi.html).

Agent instructions can require tools to release large objects after use and
close persistent kernels or transports when their owning task completes, after
preserving needed results. Such instructions are cooperative; a Nix resource
limit does not repair application object retention. Age, sleeping state and low
CPU use are insufficient grounds for an unattended process reaper. Task-aware
cleanup must distinguish a waiting active task from completed work.

Keep oomd focused on replaceable queued jobs. Broadening it to all user apps can
kill an eligible group containing valuable interactive state. Existing OOM event
counters include earlier activity and may include deliberate probes; this audit
did not attribute them to uncontrolled failures.
[systemd-oomd behavior](https://github.com/systemd/systemd/blob/v261.3/man/systemd-oomd.service.xml).

### Priority 3: measure VM tuning before declaring it policy

Live values were swappiness=10, page-cluster=3, vfs_cache_pressure=50 and
watermark_scale_factor=10. No explicit assignment for these was found in the
reviewed host, home or shared Nix modules; kernel defaults or external runtime
settings remain possible. Establish provenance before making an override.

Test swappiness 10 against 60 as one experiment under the same interactive and
background workload. Record PSI, swap traffic, zram RAM/CPU use, application
switch latency and build completion time. This is a test proposal, not a claim
that 60 is optimal. The kernel allows values above 100 for cheap in-memory swap,
but this host also uses disk swap. Leave other VM knobs unchanged during the
comparison. Routine cache flushing adds re-read cost and is discouraged by the
kernel. [Kernel VM tuning](https://docs.kernel.org/admin-guide/sysctl/vm.html).

Do not tighten swap limits as a disk-only optimization: they also constrain
zram. Do not add a small zram resident cap as an assumed spill mechanism.
[Swap controls](https://docs.kernel.org/admin-guide/cgroup-v2.html#memory-interface-files),
[zram limits](https://docs.kernel.org/admin-guide/blockdev/zram.html).

## Validation and limits

Read-only checks used systemctl show, cgroup memory/pressure/event files,
oomctl dump, sysctl, zramctl, swapon, CPU profile files, and short vmstat samples.
Configuration and effective settings were compared without Nix evaluation or a
system build. No services were restarted and no settings were activated in this
audit. Current samples were taken during normal concurrent desktop work, not a
controlled benchmark. Earlier explicitly authorized session cleanup is separate
from this configuration audit.

Before implementing containment, test fresh launch, relaunch, embedded browsing,
and long-running tools; confirm that unrelated applications are excluded. Then
validate generated units and run representative interaction/build comparisons.
Use the [desktop workload runner](../operations/desktop-memory-management.md)
for heavy checks. Keep changes individually reversible and reject settings that
introduce visible stalls, tool loss or unacceptable background slowdown.

## Follow-up: make pressure observations useful for policy review

Reviewed: 2026-10-17. Sources: current kernel documentation and systemd 261.3 documentation. Scope: the existing desktop memory budgets and Codex pressure monitor; source review only, with no runtime modification or workload benchmark performed for this section.

### Answer

Keep the existing containment budgets and configured compiler parallelism until representative measurements justify a change. Improve the monitor first: retain bounded private history, observe the build daemon and queued workloads independently of Codex, and record enforcement events alongside pressure. These are measurement recommendations inferred from the source behavior below; upstream does not prescribe this monitor's thresholds or history size.

### Evidence and implications

- **Pressure measures impact.** PSI distinguishes partial stalls (`some`) from simultaneous stalls of all non-idle tasks (`full`), and exposes moving averages plus cumulative microseconds. Retain both forms and their sample interval. A subgroup can be stalled while the host continues useful work, so label each scope separately. A host warning alone does not identify Codex as the cause. The existing full/avg60 warning can remain conservative while history captures earlier partial stalls. [Kernel PSI](https://docs.kernel.org/accounting/psi.html).
- **Separate protection, throttling, and containment.** systemd recommends `MemoryHigh=` as the primary control and `MemoryMax=` as the final defense; exceeding high can heavily slow a workload, while an unreclaimable max breach can invoke OOM. `MemoryLow=` protects against reclaim subject to the hierarchy. Therefore, reclaim stalls warrant comparing the affected group's effective limits and measured headroom before changing any budget. Do not infer a need for fewer compiler jobs from utilization alone. [systemd resource controls, v261.3](https://github.com/systemd/systemd/blob/v261.3/man/systemd.resource-control.xml).
- **Counters need scope and deltas.** `memory.events` includes descendants by default; `memory.events.local` isolates events at that group. A `high` increase records throttling/direct reclaim, while `max`, `oom`, and `oom_kill` distinguish later outcomes. Collect both sets for named groups and compare consecutive compatible samples. Reset the baseline when the group is recreated, the system boots, or counters decrease. A parent total must not be added to descendant totals. Preserve actual `memory.current`/swap/limit values: limits are hierarchical, and current memory includes more than anonymous process allocations. [Kernel cgroup memory interface](https://docs.kernel.org/admin-guide/cgroup-v2.html#memory-interface-files).
- **Occupancy is context.** `MemAvailable` estimates RAM available for new applications without swapping; it is not the same as free RAM. Capture it with swap occupancy and PSI. Swap usage without measured stalls or swap traffic does not by itself establish active thrashing. [Kernel proc documentation](https://docs.kernel.org/filesystems/proc.html#meminfo), [Kernel PSI](https://docs.kernel.org/accounting/psi.html).
- **Keep session ownership.** systemd documents `PartOf=graphical-session.target` for services that stop with the graphical session, and `.wants/` links for independent activation. The existing monitor/timer arrangement follows that model. [systemd special units, v261.3](https://github.com/systemd/systemd/blob/v261.3/man/systemd.special.xml). `OnActiveSec=` plus `OnUnitInactiveSec=` provides a first sample and a delay after each completion. Monotonic timers normally pause during suspend; `AccuracySec=` coalesces wakeups. Keep the current bounded polling interval and accuracy unless measured overhead or detection latency warrants change. [systemd timers, v261.3](https://github.com/systemd/systemd/blob/v261.3/man/systemd.timer.xml).

### Implementation and acceptance guidance

The current monitor overwrites its only sample and reads only Codex and host full/avg60 pressure. It cannot reconstruct the previous build's reclaim episode or identify an alternative constrained group. A bounded rolling history and independently named group readings address that evidence gap without changing application behavior. A count cap and age cap are local design choices; neither a particular retention period nor a more aggressive notification threshold is established by upstream research.

Keep history private and size-bounded, avoid process command lines and environment capture, and preserve the existing warning debounce/cooldown. Record unavailable groups explicitly; one disappearing or inaccessible group should not erase valid host/other-group evidence. Handle stale samples, clock changes and cgroup recreation without generating false event deltas. Tests should cover these observable recovery paths and verify that cold swap remains quiet. Validate the monitor's CPU/runtime and retained file size locally before claiming negligible overhead.

No source above justifies terminating active applications, automatically raising or lowering caps, flushing caches, reducing configured compiler jobs, or reaping helpers by age. Task completion remains the cleanup boundary. After representative usage, use the retained samples with interaction latency and build completion results to decide whether any budget itself needs adjustment.

### Local observations and implemented follow-up

A fresh desktop launch placed the renderer and backend under the shared Codex
slice. Its observed peak was about 12.3 GiB, below the 14 GiB high threshold;
its high, max, OOM and OOM-kill counters were zero. The monitor service had
succeeded, with about 11 MiB peak memory and 49 ms CPU for one invocation.
These are operational samples, not interaction-latency or throughput benchmarks.

The daemon and queued-workload groups had historical high-limit events without
max or OOM events. Those cumulative counts cannot identify a current regression,
and the old latest-sample-only monitor could not reconstruct earlier episodes.
No automatic cleanup by age, memory cap change, VM tuning or compiler-count
change is justified by these observations alone.

The follow-up retains the existing warning policy and records independent group
readings, partial/full PSI, effective local limits, available host RAM and event
deltas. Append-only private JSONL history rotates between two files of at most
1 MiB each. The size is a local retention choice; retention time varies with
record size. No process arguments, environment or conversation data is captured.
Cgroup generation, boot changes, counter decreases and stale samples reset the
delta baseline. Existing notification cooldowns survive the schema upgrade.
Warnings name concurrently stalled monitored groups without claiming causation.

During follow-up validation, the small behavior suite completed in the feedback
lane. Evaluation of an isolated generated-policy output nevertheless reached
about 1.1 GiB under that lane's 1 GiB high threshold, with roughly 21% full memory
pressure over one minute and no OOM. That evaluation was cancelled and moved to
the ordinary bulk lane; passing the behavior suite did not count as a generated
policy build pass. This supports routing full host/home evaluation to bulk even
when the requested output itself is small. Feedback limits and compiler counts
remain unchanged.

Follow-up validation passed ten fixture-based behavior cases in the Nix check,
Ruff lint/format, focused type checking and independent read-only review. The
cgroup-generation regression failed against the captured pre-fix monitor and
passed after the correction. The isolated generated policy built in bulk.
Monitor-only activation preserved the running application/backend identities,
profile and existing memory budgets. A live invocation used about 11.2 MiB peak
memory and 68 ms CPU and created a 0600 history file. Rotation bounds are covered
by fixtures; a representative long-term workload or throughput comparison has
not been performed. No application restart, process migration or global tuning
was part of this follow-up.

### Later freeze investigation: reclaim threshold calibration

A later 2026-10-17 capture supersedes the earlier decision to retain the 14 GiB
high threshold. While investigating reported UI freezing, a 30-second read-only sample caught
23,695 new high-limit events and 11.14% full memory stalls within the Codex
slice. The main renderer incurred 124,681 major page faults and was in
uninterruptible I/O sleep in nine one-second observations. There were no max or
OOM events. The host still had substantial available memory; adjacent samples
reported roughly 10–14 GiB. This is evidence of a restrictive group threshold,
not evidence that the host had exhausted RAM.

The group also held substantial filesystem cache. Cgroup memory usage includes
file-backed cache as well as anonymous allocations; a resident process-size
estimate alone does not establish an adequate group budget.
[Kernel memory interface](https://docs.kernel.org/admin-guide/cgroup-v2.html#memory-interface-files).
The kernel explicitly documents that exceeding `memory.high` throttles processes
and forces reclaim, and that an overly aggressive high threshold can degrade
performance without OOM-killing anything.
[Kernel high-limit behavior](https://docs.kernel.org/admin-guide/cgroup-v2.html#memory-interface-files).

A live trial changed only the Codex high threshold from 14 to 16 GiB. The hard
18 GiB memory ceiling and 10 GiB swap ceiling were unchanged. In the next
30-second sample, high-limit events did not increase, full group stalls fell to
0.13%, renderer major faults fell to 293, and no renderer observations were in
uninterruptible I/O sleep. Application and backend processes were preserved.
The declared high threshold is therefore calibrated to 16 GiB, leaving 2 GiB
below the unchanged hard ceiling.

These are consecutive live observations with concurrent work, not a controlled
replay of identical UI actions. They establish that the measured reclaim episode
subsided after the adjustment; user confirmation and longer observation are
needed before declaring every visible freeze resolved. Repeated application
layout errors were also observed, but their causal role was not established.
No caches were flushed, active tasks killed, global VM settings changed or
application processes restarted for the comparison.

A subsequent chat-switching comparison found 94,885 major faults in another
renderer on its first observed switch window, falling to 36 in a later window;
its uninterruptible-sleep observations fell from two to zero. Neither window
added high-limit events. The reported interaction also became faster after the
first switch. This is consistent with already-evicted pages returning to RAM,
and distinguishes that residual cold-page cost from ongoing high-limit reclaim.
The 16 GiB policy and monitor configuration built successfully and were activated
without restarting the app. The temporary runtime override was removed after
the generated unit took ownership, so it cannot mask later declarative changes.
Formatting, documentation checks and process-identity/limit checks cover the
change; no memory-exhaustion stress test was run against the interactive app.

## Follow-up: retained tool processes and deployed policy drift

A 2026-10-21 audit found about 9 GiB of available host RAM despite less than
1 GiB being completely unused. Host memory PSI was quiet during the sampled
interval. Roughly 31 GiB of occupied swap therefore did not, by itself, establish
current memory exhaustion. Compressed swap held about 13 GiB of logical data in
4 GiB of physical storage; those logical and physical figures must not be added.
[Kernel memory accounting](https://docs.kernel.org/filesystems/proc.html#meminfo),
[kernel PSI](https://docs.kernel.org/accounting/psi.html),
[zram accounting](https://docs.kernel.org/admin-guide/blockdev/zram.html).

The complete application group held approximately 7 GiB resident and 15 GiB
swapped. A running 8 GiB Windows guest accounted for about 4.5 GiB resident and
3.7 GiB swapped. Application descendants included 79 browser/tool server
processes, 38 security-plugin servers, and 54 computer-use REPL servers. The
first two categories together reported roughly 2.6 GiB RSS and 5.2 GiB swap.
These process estimates overlap the application-group total and RSS can count
shared pages more than once. Process count and inactivity do not establish
that a task is complete; automatic process termination was not justified.

The live application high threshold had reverted to 14 GiB through an older
scoped swap preview, although the declared threshold was 16 GiB. The running
monitor also retained the earlier 10 GiB swap warning budget and lacked the
newer pressure history. A scoped user-unit rollout restored the declared
16 GiB high threshold while preserving both 18 GiB hard limits, and installed
the existing reviewed monitor with matching warning settings. A separate local
GC root retains both preview unit closures until normal managed activation
owns both links. Application, backend and VM process identities were preserved.
This prevents policy drift from reintroducing the earlier reclaim threshold;
it does not demonstrate reduced application retention or a measured RAM saving.

The existing ten focused resource tests and disposable live integration probe
passed. Unit verification passed, the live monitor exited successfully, and its
snapshot recorded the effective limits, available RAM, independent group event
counters and bounded pressure history. The first post-rollout sample showed
no host memory stalls. This is bounded verification, not a long-running UI or
memory-exhaustion test. No full system build or activation was performed.

Do not add Windows free-page reporting based only on libvirt's XML support.
The inspected upstream Windows balloon driver negotiates statistics and creates
inflate, deflate and statistics queues, without a reporting queue. Enabling an
XML flag alone would not establish a working guest memory recovery path.
[Libvirt balloon configuration](https://libvirt.org/formatdomain.html#memory-balloon-device),
[Windows virtio balloon source](https://github.com/virtio-win/kvm-guest-drivers-windows/blob/master/Balloon/sys/balloon.c).

The next substantial reduction should come from native cleanup when tool-owning
tasks finish, or normal guest shutdown when its applications are no longer
needed. Preserve active task state. Avoid periodic cache flushing, swap cycling,
or reclaiming the active application merely to change the free-memory display;
rebuilding discarded caches adds CPU and I/O work.
[Kernel VM guidance](https://docs.kernel.org/admin-guide/sysctl/vm.html).

## Follow-up: service heaps and Windows allocation (2026-11-03)

This follow-up measures working sets rather than inferring consumption from
configured ceilings. Captures include PSS, proportional swap, cgroup anonymous
memory, file cache, pressure and limit events. Raw captures remain private.
Concurrent applications make these observations an audit, not a benchmark.

The largest consumers were the desktop agent application and Windows. The guest
used about 4.1 GiB host PSS plus 3.9 GiB proportional swap; a Windows-native sample
reported 4.4 GiB available out of its 8 GiB allocation. Swapped bytes are logical
contents, not additional physical RAM; compressed swap uses its own RAM. Agent
renderers and backend together were the largest application opportunity. Release
only helpers belonging to completed tasks; idle time does not establish ownership
or completion. Existing application grouping and workload admission remain useful.

### Java services

| Service | Observed used heap | Committed heap | Maximum heap |
| --- | ---: | ---: | ---: |
| Komga | 133 MiB | 166 MiB | 768 MiB |
| Stirling PDF | 431 MiB | 574 MiB | 1536 MiB |
| Keycloak | 106 MiB | 164 MiB | 512 MiB |
| LanguageTool | 190 MiB | 256 MiB | 7740 MiB |

Maximum heap is an allowance, not reserved physical memory. The new desktop
`workstation.memoryEfficiency.java` policy gives Stirling a 64 MiB minimum heap, preserves Komga's ergonomic
minimum, and enables concurrent periodic G1 collection every five minutes, skipped
above a one-minute host load of four. This permits heap return during idle time
without reducing existing maximum heaps or service cgroup limits. Stirling's
previous 256 MiB minimum falls by 192 MiB; that is a lower floor, not a measured
192 MiB physical saving. Per-service enable/minimum settings and the interval/load
check are configurable. Zero interval disables periodic collection. Measure idle
anonymous memory and swap after collection, GC CPU and next-request latency.
[Oracle G1 heap tuning](https://docs.oracle.com/en/java/javase/25/gctuning/garbage-first-garbage-collector-tuning.html).

Compact object headers are exposed as a disabled trial option for these Java 25
services. They reduce per-object overhead, but native buffers and metaspace are
separate. No workload saving or compatibility result is claimed for this option.
Do not apply it to the Java 21 services.
[Oracle compact object headers](https://docs.oracle.com/en/java/javase/25/gctuning/other-considerations.html).

Diagnostic limitation: attaching `jcmd` to the sandboxed PDF service triggered a
blocked `chown` syscall and one crash followed by successful automatic recovery.
The Java 25 figures above came from heap lines in the resulting journal output;
the Java 21 reads succeeded. Further attachment stopped. Preserve the sandbox;
validate future tuning with startup logging and application requests.

### Windows controls and prerequisites

`virtualisation.libvirtWorkstation.windowsVm.resources.currentMemoryMiB` now separates the runtime
allocation from `memoryMiB`, its ceiling. It defaults to the ceiling and must not
exceed it. Installer XML retains the full ceiling; reconciliation stages persistent
XML without changing a running guest. For a measured smaller profile:

```nix
virtualisation.libvirtWorkstation.windowsVm.resources = {
  memoryMiB = 8192;
  currentMemoryMiB = 6144;
};
```

This example takes effect at the next guest start. It is not enabled by this audit:
a single idle sample cannot establish representative peak demand. A 6 GiB target
could reclaim up to 2 GiB relative to 8 GiB, with reduced guest headroom.
[Libvirt memory allocation](https://libvirt.org/formatdomain.html#memory-allocation).

The balloon driver was present but its statistics user service was absent and
host statistics were stale. Installing the INF alone does not install that service.
Repair guest telemetry from pinned driver media during guest maintenance before
considering automatic ballooning. Current Windows driver support does not justify
assuming automatic deflation on guest OOM or free-page reporting; neither is a
safety guarantee for a smaller target.
[VirtIO statistics service discussion](https://github.com/virtio-win/kvm-guest-drivers-windows/issues/1323),
[Windows balloon driver](https://github.com/virtio-win/kvm-guest-drivers-windows/blob/master/Balloon/sys/balloon.c).

### Other services

ClamAV already avoids concurrent signature-database reloads; its roughly 1 GiB
logical footprint is mostly signatures. Keep full scanning coverage. Redis was
about 7 MiB including swap; its 128 MiB maximum is not a reservation. The native
homelab PostgreSQL group was below 100 MiB including swap, so blanket database
buffer reductions have little demonstrated benefit. Ollama was unloaded at about
21 MiB and already expires models after one minute; active model/context tuning
needs inference-quality and throughput checks. Preserve the calibrated backup
budget: reducing its pressure threshold previously caused reclaim stalls. No
additional hard-cap reductions are part of this change.
