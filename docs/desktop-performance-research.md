# Desktop performance review

Reviewed: 2026-09-10. Scope: responsiveness, builds, gaming, storage, network,
boot, and power use. Runtime versions were Linux 7.2.3, systemd 261.2,
Determinate Nix 3.22.3 with Nix 2.35.2, NVIDIA 595.99.02, and Hyprland 0.56.0
at `ee0409623e2d6a683374b39a32e0ac3d087841aa`.

## Answer

The observed desktop had spare CPU and memory capacity. The strongest concrete
configuration finding is that its lower background I/O weights lack an active
proportional I/O controller on either NVMe drive. Nix's memory policy has also
triggered reclaim throttling, which can trade build throughput for responsiveness.
Test those mechanisms under representative work before buying hardware.

For games, compare rendering settings and frame times at the existing 4K output.
For boot, investigate the path to the greeter separately from background service
completion. CPU power-policy changes belong in an efficiency experiment because
the current policy already favors performance.

These are ranked next steps, not measured speedups. No system configuration was
changed or activated during this review.

## Measurements

The machine has a Ryzen 7 7700X with 8 cores and 16 threads, approximately
32 GB installed RAM with 30.5 GiB visible to Linux, an RTX 4070 with 12 GiB
VRAM, an ADATA SX8200 system SSD, and a Samsung 970 EVO Plus games SSD.
Observations below came from the live system, rather than Nix evaluation.

| Area | Observation | Interpretation |
| --- | --- | --- |
| CPU | 30-second `vmstat` sample was 84–97% idle; initial CPU temperature about 50°C | No sustained CPU saturation in this sample; loaded thermal behavior remains untested |
| Memory | Initial available memory about 15 GiB; about 10.4 GiB swap occupied | Swap residency alone does not establish thrashing |
| Zram | About 9.5 GiB data occupied 3.3 GiB physical memory, including overhead | Roughly 2.9:1 effective compression; zram is providing useful capacity |
| Pressure | Separate 20.24-second sample: CPU `some` 2.05%, memory `full` 0.049%, I/O `full` 1.14% | Some activity, but little memory stall during observation |
| Storage activity | System SSD averaged 104 MiB/s reads and 7.2 MiB/s writes; 0.51 ms mean read and 10.64 ms mean write completion time | A reason to examine contention during slow work; averages cannot establish tail latency or maximum throughput |
| Storage space and health | System filesystem 62% occupied; games filesystem 45%; exporter reported healthy drives and zero NVMe media errors | No capacity or reported media-health reason for immediate replacement |
| Graphics | Actual output 3840×2160 at 240.016 Hz, scale 1.5, 10-bit format, VRR off | Verify game rendering performance separately from display refresh capability |
| Network | Wi-Fi signal −51 dBm, power saving off; gateway average 1.04 ms, zero loss over 12 packets | Local link looked responsive; internet throughput and loaded latency were not measured |
| Boot | 95.1 seconds to startup completion; greeter service started 30.9 seconds into userspace | Full service completion is not time to an interactive desktop |

The GPU varied from 0–94% utilization across ten samples while drawing about
24–40 W at 35–36°C. This was ordinary desktop activity, not a controlled idle
or gaming benchmark. It does not establish a GPU bottleneck.

The current boot's visible kernel log contained ten OOM trigger records, all in
named regression-test cgroups. Those deliberate probes must not be counted as
uncontrolled desktop OOM failures. The Nix daemon separately had 46,774 cumulative
`memory.events:high` events, zero OOM events, and approximately 51 seconds of
cumulative full memory-pressure time. These counters establish past reclaim
pressure within that cgroup, not how much a particular build slowed down.

PSI measures time stalled on resources. Zram statistics distinguish logical
data from physical allocation. Both are more informative here than a single
swap-used number. [Kernel PSI documentation](https://docs.kernel.org/accounting/psi.html),
[zram statistics](https://docs.kernel.org/admin-guide/blockdev/zram.html).

## Findings and recommendations

### 1. Establish effective background disk protection

The active daemon has `IOWeight=50` and queued development work has
`IOWeight=25`. Both NVMe devices use the `none` scheduler. Their available
schedulers were `none`, `mq-deadline`, and `kyber`; root `io.cost.qos` and
`io.cost.model` were empty. Thus the configured weights do not establish the
intended proportional disk sharing.

Linux provides proportional sharing through iocost or BFQ support. For this
NVMe configuration, investigate calibrated iocost or measured background
bandwidth limits. Do not assume changing to `mq-deadline` makes `IOWeight`
effective. Compare application-launch latency and game frame-time tails during
the same background build or copy, alongside background completion time.
[Kernel I/O controller documentation](https://docs.kernel.org/admin-guide/cgroup-v2.html#io-interface-files).

The owning policy is [the desktop memory module](../hosts/nixos/desktop/local/memory.nix).
The absence of proportional control is confirmed; its user-visible cost is not.

### 2. Tune build throughput within the existing memory policy

The effective Nix client settings are `max-jobs=2`, `cores=4`, and
`eval-cores=0`. The daemon has a 6 GiB slowdown threshold, 8 GiB hard limit,
and 1 GiB swap limit. Queued development work separately has 8/10 GiB memory
thresholds and a 2 GiB swap limit. Desktop memory protections are active.

Keep that baseline for multitasking. For a single CPU-bound derivation, test
one job with eight cores against the existing two-job/four-core policy. For
memory-heavy evaluation, compare `--eval-cores 4` against automatic parallelism.
Run experiments through [the workload runner](desktop-memory-management.md),
recording elapsed time, peak memory, pressure, and changes to `memory.events`.
Increasing concurrency without those measurements can make either result worse.

`cores` is a builder hint; `max-jobs` controls concurrent derivations. The
installed client's help confirms that `eval-cores=0` uses all available CPUs
for supported parallel evaluation paths.
[Nix cores versus jobs](https://nix.dev/manual/nix/2.31/advanced-topics/cores-vs-jobs.html),
[Determinate parallel evaluation](https://docs.determinate.systems/determinate-nix/parallel-eval/).

`MemoryHigh` deliberately throttles allocations and reclaims memory. If repeat
builds accumulate high events while interactive memory headroom remains ample,
compare a carefully increased daemon threshold. Preserve a hard limit and test
with applications open. CPU weights compare siblings, so weights in
`system.slice` and `user.slice` are not directly comparable.
[systemd resource-control source](https://github.com/systemd/systemd/blob/v261.2/man/systemd.resource-control.xml).

### 3. Reduce unnecessary source builds before adding CPU threads

[The host profile](../hosts/nixos/desktop/default.nix) enables `cudaSupport`
globally. This can change optional dependencies and package variants. Audit the
actual applications that need CUDA, then compare derivations and substitute
availability for targeted overrides. A smaller CUDA scope may reduce builds and
closure size, but this review did not quantify that effect.
[Nixpkgs CUDA configuration](https://nixos.org/manual/nixpkgs/unstable/#cuda).

CUDA, Hyprland, Noctalia, nix-community, NixOS, and FlakeHub caches are already
present in effective configuration. Measure misses for the exact pinned outputs.
Adding duplicate caches does not help. Avoid custom CUDA architecture lists
until their benefit exceeds the cost of losing matching cached artifacts.
[NixOS CUDA infrastructure](https://nixos-cuda.org/).

Automatic store deduplication is enabled and the system has substantial free
space. If build completion or package installation shows metadata-I/O stalls,
compare automatic deduplication against scheduled optimization as a secondary
experiment. No evidence yet attributes the observed I/O to this setting.
[Nix configuration reference](https://nix.dev/manual/nix/2.35/command-ref/conf-file.html#conf-auto-optimise-store).

### 4. Improve game frame times with a measured rendering budget

At 240 Hz, a refresh interval is 4.17 ms. Native 4K contains 2.25 times as many
pixels as 1440p. Keep the sharp 4K desktop; in GPU-bound games, compare DLSS
Super Resolution or lower internal rendering resolution. Compare ray-tracing
settings and choose a stable frame cap from measured results. Enable Reflex
where supported. Record base rendering FPS and latency separately from any
frame-generation output. [NVIDIA Linux gaming guide](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/gaming.html).

[The display policy](../homes/desktop/local/hyprland.nix) disables VRR because
some games flicker. Preserve that choice. Fullscreen-only VRR is an optional
per-game experiment, not a missing baseline. Game-only direct scanout is another
candidate if composition contributes meaningful overhead; test HDR, overlays,
capture, and alt-tab along with frame times.
[Hyprland variables](https://wiki.hypr.land/Configuring/Basics/Variables/).

GameMode is already selected. Its presence does not prove a game launches
through it. Verify an actual game session before adding another tuning service.
The installed NVIDIA driver is already newer than the explicit-sync minimum
documented by Hyprland; old driver workarounds are not a justified first step.
[Hyprland NVIDIA guidance](https://wiki.hypr.land/Nvidia/).

### 5. Investigate boot delays and finish pending activation repairs

Firmware accounted for 17.6 seconds, loader 5.7 seconds, kernel/initrd about
6.5 seconds, and userspace 65.3 seconds. The greeter starts earlier, at 30.9
seconds of userspace. `flakehub-login` took 34.3 seconds but was not on the
greeter's reported critical chain. `systemd-rfkill` took 26.4 seconds, while
local filesystem initialization completed around 27.5 seconds into userspace.

Capture a boot timing plot and investigate early device, filesystem, and rfkill
ordering before changing dependencies. Inspect ClamAV startup ordering when
measuring full target completion. Do not add service durations together or
assume removing authentication would save 34 seconds at login.
[systemd-analyze source](https://github.com/systemd/systemd/blob/v261.2/man/systemd-analyze.xml).

The running Home Manager unit failed on a conflicting Hyprland configuration
file. The document portal also exited with status 21 later in the session.
These are reliability findings; neither failure establishes a general CPU
performance problem. The checkout already contains conflict-preservation logic
in [the home memory module](../homes/desktop/local/memory.nix), and
[the FlakeHub unit](../hosts/nixos/desktop/nix-seal.nix) already orders login
after the multi-user target. Verify the intended generation and successful
activation instead of duplicating those fixes. This review did not restart
services or activate the checkout.

### 6. Keep useful memory and storage defaults

Zstd zram is compressing effectively. Current swappiness is 60, page-cluster
is 3, transparent huge pages use `madvise`, and multigenerational LRU is enabled.
There is no measurement supporting a blanket swap reduction or disabling these
mechanisms. Higher swappiness or page-cluster 0 can be tested under repeatable
pressure, but this system also has slower disk swap, so a pure-zram recipe
does not directly apply. [Linux VM controls](https://docs.kernel.org/admin-guide/sysctl/vm.html).

`/tmp` is tmpfs, with 1.7 GiB occupied during inspection. If a build's temporary
files are the measured memory bottleneck, compare a disk-backed build directory.
Retaining tmpfs for smaller temporary work remains reasonable. Disk-backed
scratch trades RAM headroom for storage I/O.
[Kernel tmpfs documentation](https://docs.kernel.org/filesystems/tmpfs.html).

The filesystems already use `noatime` and `compress=zstd:1`; weekly TRIM is active.
The checkout deliberately chooses `nodiscard` and periodic maintenance.
Asynchronous discard is supported upstream, but is an alternative requiring a
comparison, not an automatically faster replacement. Preserve the existing
[storage plan](desktop-storage-research.md).
[Btrfs discard documentation](https://btrfs.readthedocs.io/en/latest/Trim.html).

### 7. Treat power and hardware changes as conditional choices

The active CPU driver, governor, EPP, and desktop power profile already favor
performance. Test the existing power-profile service's balanced mode for lower
power and fan noise, then inspect the resulting governor/EPP. Compare sustained
compile time and game frame-time tails before choosing it. This is an efficiency
experiment, not an assumed speedup.
[AMD P-state documentation](https://docs.kernel.org/admin-guide/pm/amd-pstate.html).

No purchase is justified by the sampled idle capacity alone. If normal builds,
VMs, and applications repeatedly cause pressure, 64 GB RAM is the first capacity
upgrade to investigate. If a representative game remains GPU-bound at desired
settings after rendering adjustments, evaluate a GPU upgrade. Consider a faster
system SSD only after storage-latency measurements implicate it. RAM speed,
firmware settings, and sustained thermal behavior remain unverified.

The current Wi-Fi gateway latency is good. Compare wired Ethernet if loaded
network latency or large transfers are a problem; the short local ping says
nothing about WAN throughput. Keep the documented CUBIC policy until network
measurements support a different congestion-control choice.

## Validation and limits

This review used read-only `/proc` and sysfs measurements, two short activity
samples, process memory counters, effective Nix settings, systemd policy and
journals, display/GPU queries, the local Telegraf exporter, and a twelve-packet
gateway probe. The first `vmstat` row reports averages since boot and was
excluded from interval interpretation. SSD completion means came from block
counter deltas; they are not latency percentiles. Raw captures remain outside
the repository in private temporary storage.

Direct SMART, DMI memory, and Btrfs device-stat commands required an unavailable
sudo password. SMART observations therefore come from the configured exporter;
they are not a fresh full device self-test. Several motherboard sensor fields
were unreadable or ambiguous, so they were not used to diagnose overheating.

The root base was `7fd38c80a2aabdb16674fba7231496fa4a575bee`, with substantial
pre-existing working changes. Runtime settings and checkout intent were examined
separately. No system build, activation, stress test, game benchmark, bandwidth
test, firmware change, or cleanup ran. All proposed performance gains remain
unmeasured. Browser video decoding, VM workloads, application-launch latency,
and editor interaction were not benchmarked. Upstream sources were retrieved
on the review date.

The next comparison should hold applications and workload constant, change one
setting, and repeat each condition at least three times. Record median task
completion, peak memory, pressure deltas, and application or frame-time tails.
Separate warm-cache results from fresh builds. Accept a change only if its
benefit exceeds run-to-run variation and its responsiveness tradeoff is acceptable.

## Implementation follow-up

The subsequent repair pass implemented the following changes. The measurements
above describe the original inspection, before these repairs.

| Finding | Repair and verification | Deployment state |
| --- | --- | --- |
| NVMe weights had no proportional controller | Added adaptive `iocost`, retained scheduler `none`, and gave `user.slice` weight 200. A NixOS VM passed cold-start, udev reapplication, service restart, and slice-weight checks. | Built and tested; administrator activation remains pending. |
| Nix evaluation defaulted to all available CPUs | Set `eval-cores = 4`, retaining two builds and four cores per build. Alternating local evaluations supported this bound. | Configuration evaluation passed; system activation pending. |
| Global CUDA selection could change unrelated package variants | Disabled global CUDA and explicitly retained CUDA for Sunshine and its cache. The pinned Sunshine derivation stayed unchanged. | Configuration evaluation passed; system activation pending. |
| Workload launcher expanded quoted dollar expressions | Added `systemd-run --expand-environment=no` and regression assertions. Installed and tested the corrected user-profile launcher. | Live. |
| Document portal failed | Restarted the user portal and verified its D-Bus owner and FUSE mount. Isolated the VS Code font probe's runtime directory as well as its private bus. | Portal live; corrected probe passed without replacing it. |
| Home Manager collided with a foreign Hyprland symlink | Verified the existing pending preservation hook rather than adding another migration. | Source verified; activation pending. |
| Startup waited for unrelated services | Verified existing ClamAV and FlakeHub ordering repairs. Added asynchronous USB-audio probing after identifying repeated device-request timeouts. | Source verified; next-boot timing remains untested. |

The evaluator comparison used three runs at four threads and three at sixteen,
alternating configurations against the same package-derivation evaluation. Four
threads took 7.016 to 7.418 seconds with peak resident memory of 2213 to 2222 MiB.
Sixteen took 7.417 to 7.618 seconds and 2249 to 2267 MiB. This supports avoiding
extra evaluator concurrency for this workload. It does not establish a general
build-speed improvement, and the desktop was not otherwise idle.

The `iocost` policy uses the kernel's adaptive model because these drives lack a
device-specific hwdb profile. It skips drives with an `IOCOST_SOLUTIONS` profile
so systemd retains ownership of calibrated settings. Controller activation and
weight propagation passed the VM test; throughput and foreground latency under
real contention have not yet been compared.
[Linux I/O cost controller](https://docs.kernel.org/admin-guide/cgroup-v2.html#io-interface-files).

The audio setting addresses a possible boot serialization delay, not the device's
underlying request timeouts. In the pinned Linux 7.2.3 source, `async_probe=1`
allows the module loader to return without waiting for asynchronous probes.
Other synchronization points can still wait. Keep this as a measured next-boot
comparison, with audio functionality checked alongside startup timing.
[Module initialization](https://github.com/gregkh/linux/blob/v7.2.3/kernel/module/main.c#L3138),
[async probe parameter](https://github.com/gregkh/linux/blob/v7.2.3/kernel/module/main.c#L3372).

Targeted policy builds, the I/O VM test, memory-policy and cache-policy checks,
shell checks, and the corrected native font probe passed. An independent review
found no remaining defects in the implementation patch. The first I/O VM run
used an incorrect assumption about its default scheduler; the corrected fixture
explicitly selected the desktop's `none` scheduler. The first font-probe repair
left a helper scope running; that scope was stopped and the final isolated probe
exited cleanly. Neither failed attempt counts as successful validation.

The system manager denied the targeted privileged I/O apply attempt. No full
system activation or reboot ran during this repair pass. Existing encrypted-swap
deployment guards remain in place. A later coordinated deployment must preserve
those guards and verify the I/O controller, evaluator settings, startup services,
Home Manager activation, and USB audio on the running generation.

The inspection did not justify changes to zram, display resolution, refresh rate,
VRR, power policy, congestion control, or hardware purchases. Those recommendations
remain conditional on the workload measurements described above.
