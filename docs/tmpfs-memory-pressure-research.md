# Tmpfs and memory pressure

Reviewed: 2026-09-14. Scope: the interactive-system temporary-filesystem policy and its
interaction with the systemd cgroup-v2 memory policy. The configured systemd
version was 261.2; the installed NixOS reported 26.11.20260905.c043004. Sources
were retrieved on 2026-09-14.

## Answer

The safest configuration change is to make `/tmp` disk-backed again and enable
boot-time cleanup:

```nix
boot.tmp = {
  useTmpfs = false;
  cleanOnBoot = true;
};
```

This removes a large, writable, swap-backed filesystem from the interactive
RAM budget while retaining the usual temporary-data lifecycle across boots.
It is a better first fix than making the existing tmpfs smaller or imposing a
hard cap on the Chromium application scope. A bounded tmpfs turns this failure
mode into `ENOSPC`; a browser hard limit turns it into an in-cgroup OOM and can
discard interactive work. Neither addresses files left in `/tmp` after the
writer has exited.

This policy is now applied in
[`hosts/nixos/desktop/local/system.nix`](../hosts/nixos/desktop/local/system.nix).
It needs activation and a reboot before the live mount changes. The change does
not delete the current `/tmp`; `cleanOnBoot` takes effect during a later boot.
The root filesystem had roughly 298 GiB free during the investigation, but a
reboot-time check should still confirm enough space for the largest supported
build scratch workload.

## Findings and sources

### Observations from the affected configuration

- `/tmp` is currently a 16 GiB tmpfs, approximately 15 GiB occupied. Its
  largest top-level entries are development work trees and package caches.
  This is a redacted local observation, not a general property of NixOS.
- The system configuration at measurement time set `boot.tmp.useTmpfs = true`.
  Evaluation confirms the NixOS default
  `boot.tmp.tmpfsSize` is `"50%"` and `boot.tmp.cleanOnBoot` is false, so the
  active configuration produces the observed 16 GiB capacity limit.
- The background workload policy applies `MemoryHigh=8G`, `MemoryMax=10G`,
  `MemorySwapMax=2G`, and
  pressure-based `systemd-oomd` handling to `background-workload.slice`.
  It does not limit unrelated application scopes.
- The interactive application policy at measurement time gave the
  Chromium-named scope `OOMPolicy=continue`, but no memory or swap ceiling.
  The repository now adds a measured browser-family budget described below.
- After a build had exited, the workload slice had no tasks but still showed
  roughly 3.6 GiB of `shmem` or tmpfs charge. This is a redacted local
  observation. It is consistent with cgroup-v2 accounting: `memory.stat`
  reports tmpfs and shared memory as `file` and `shmem`, and memory ownership
  is stateful per page until the page is released. It does not prove which
  process created every retained page. [Kernel cgroup-v2 documentation](https://docs.kernel.org/admin-guide/cgroup-v2.html#memory-interface-files)
  and [kernel source documentation on memory ownership](https://github.com/torvalds/linux/blob/master/Documentation/admin-guide/cgroup-v2.rst)
  support that interpretation.

### tmpfs is part of the memory problem

**Source fact.** tmpfs keeps files in virtual memory, grows and shrinks with
its contents, and may swap unneeded pages when swap is enabled. Its `size=`
option limits allocated bytes. The kernel warns that oversizing tmpfs can
deadlock a machine because the OOM handler cannot free that memory. It also
reports tmpfs pages as `Shmem` and recommends `df` and `du` for the most
reliable size count. [Linux kernel tmpfs documentation](https://docs.kernel.org/filesystems/tmpfs.html)

**Source fact.** The NixOS module implements `boot.tmp.useTmpfs` as a systemd
mount of tmpfs at `/tmp`, passes `size=${boot.tmp.tmpfsSize}`, and defaults the
size option to `"50%"`. Its option text warns that large Nix builds may fail
when tmpfs is too small and says to increase the size or disable tmpfs.
`boot.tmp.cleanOnBoot` adds the `D! /tmp` tmpfiles rule. [NixOS tmp module at
the installed revision](https://github.com/NixOS/nixpkgs/blob/c043004/nixos/modules/system/boot/tmp.nix)

**Inference.** The current temporary filesystem can consume almost half of
physical RAM before it reports full. That capacity is large enough to crowd
out applications, kernel memory, and compressed swap during a build. A 15 GiB
used tmpfs is therefore a credible primary contributor to the reported RAM
pressure. It is not proof that tmpfs alone caused every OOM event.

### Cleanup policy is useful, but not pressure control

**Source fact.** systemd-tmpfiles `d` and `e` entries clean directory contents
by age. If the age is omitted, no automatic cleanup occurs; an age of zero
cleans contents whenever `systemd-tmpfiles --clean` runs. `D` also removes
contents when tmpfiles runs with `--remove`. [systemd tmpfiles.d 261.2](https://github.com/systemd/systemd/blob/v261.2/man/tmpfiles.d.xml)

**Inference.** Boot cleanup is appropriate for disk-backed `/tmp`: it restores
the conventional expectation that old scratch data does not survive a reboot.
An age-based cleanup rule can reduce long-lived clutter, but it runs later and
must not be presented as protection against a current 15 GiB allocation.
Avoid a broad age rule until the owners and normal lifetimes of the top-level
directories are understood. A rule that deletes an active compiler cache or
work tree would be worse than the original memory problem.

### cgroup limits and oomd have distinct jobs

**Source fact.** `MemoryHigh=` maps to `memory.high`: exceeding it throttles
the cgroup and forces aggressive reclaim, but does not itself invoke the OOM
killer. systemd calls it the main memory-use control. `MemoryMax=` maps to
`memory.max`: if reclaim cannot bring use under the hard limit, the kernel
invokes an OOM killer inside that cgroup; systemd calls it the last line of
defense. `MemorySwapMax=` maps to `memory.swap.max`, a hard limit on the
cgroup's swap use. [systemd resource control 261.2](https://github.com/systemd/systemd/blob/v261.2/man/systemd.resource-control.xml)
The matching [kernel cgroup-v2 documentation](https://docs.kernel.org/admin-guide/cgroup-v2.html#memory-interface-files)
also says `memory.high` is the main control mechanism, `memory.max` can
temporarily be exceeded, and a cgroup OOM does not kill tasks outside that
cgroup.

**Source fact.** systemd-oomd monitors units configured with
`ManagedOOMMemoryPressure=kill` or `ManagedOOMSwap=kill` using cgroup-v2 PSI.
When a limit is met, it selects an eligible descendant cgroup and sends
`SIGKILL` to its processes. It needs memory accounting and works best with swap
enabled. [systemd-oomd 261.2](https://github.com/systemd/systemd/blob/v261.2/man/systemd-oomd.service.xml)

**Inference.** The existing workload slice is a sensible boundary for queued,
replaceable work. Its limits and oomd policy cannot constrain memory charged by
an application scope, nor can they erase tmpfs data that remains charged after
the build's processes exit. The retained charge is a reason to fix the storage
policy instead of simply lowering the workload budget.

### When an application ceiling is justified

**Source fact.** Resource controls apply to scopes as well as services and
slices, and cgroup controllers are hierarchical. A child cannot override a
stricter parent restriction. [systemd resource control 261.2](https://github.com/systemd/systemd/blob/v261.2/man/systemd.resource-control.xml)

**Inference.** Adding `MemoryHigh`, `MemoryMax`, and `MemorySwapMax` to the
Chromium-derived scope can contain that scope, but the hard limit can kill a
renderer, helper, or the whole application group. `OOMPolicy=continue` only
controls systemd's reaction after an OOM victim; it does not prevent the kernel
from choosing that victim. Here, fresh measurements found a long-lived scope
with nearly 8 GiB resident use and a historical peak around 21 GiB including
swap, so the repository now applies a measured `10G`/`12G`/`4G`
`MemoryHigh`/`MemoryMax`/`MemorySwapMax` policy. This is a containment measure,
not a claim that the application has no leak; its recovery behavior still needs
validation after activation.

## Options considered

| Option | Pressure result | Main cost | Decision |
| --- | --- | --- | --- |
| Keep tmpfs and set a smaller `tmpfsSize` | Caps `/tmp` allocation | Build and tool failures at `ENOSPC`; still reserves memory pressure up to the cap | Do not choose first |
| Keep current tmpfs and add scheduled cleanup | May remove old files later | Cannot stop an active allocation; lifetime rules risk deleting useful data | Supplement only after inventory |
| Use disk-backed `/tmp` and clean on boot | Moves durable backing to the filesystem; memory cache can be written back and reclaimed | Requires sufficient disk capacity; files last until reboot | Recommended |
| Add measured Chromium scope ceilings | Limits one application cgroup | Application-local OOM and lost interactive work; does not clear retained tmpfs | Apply 10G/12G/4G policy after measurement |

## Validation and limits

Documentation review used the Linux kernel documentation retrieved on
2026-09-14, systemd v261.2 source documentation, and the NixOS tmp module at
the installed `c043004` revision. Local read-only checks confirmed the tmpfs
mount type, its approximate occupancy, NixOS option values, and the relevant
declarative policies. The repository now contains the disk-backed `/tmp` and
browser-scope changes; no files were deleted and no system activation ran.

This investigation did not identify every writer in `/tmp`, measure the disk
space available to a disk-backed `/tmp`, or run a controlled memory-pressure
workload. The observed residual charge is evidence of the problem, not a
complete allocation trace. Those gaps matter before selecting any numeric
browser limit or an age-based cleanup rule.

## Implication for this repository

The affected system policy now uses the disk-backed, clean-on-boot policy above
and includes the measured Chromium scope budget. Evaluate the target
configuration before activation. After activation and a reboot, verify the
`/tmp` mount type, free disk space, normal Nix build behavior, the absence of
persistent scratch data from the previous boot, and the effective Chromium
limits. Keep the existing workload slice policy; it remains the primary control
for replaceable development work.
