# Scheduled Restic backup performance

Reviewed: 2026-10-21. Scope: Restic 0.19.1 on Linux and systemd 261.

## Answer

Separate logical source size, newly stored data, repository-index memory, and
kernel reclaim when diagnosing a slow backup. A small stored delta does not
make a large file tree cheap to scan. Preserve a stable source set, exclude
filesystem snapshot trees and regenerable caches, and allow the index working
set to fit before tuning concurrency.

## Findings and sources

Restic groups parent snapshots by host and source paths. It compares metadata
for unchanged files; renamed paths require another content scan. Processed bytes
and newly stored bytes are different measurements. Keep paths stable instead of
using force or ignore-metadata flags as a general performance workaround.
[Restic backup and change detection](https://restic.readthedocs.io/en/stable/040_backup.html#file-change-detection).

Nix module option defaults disappear when another module defines the option.
A baseline exclusion list must be a normal ordered definition if host additions
must preserve it. The backup module uses `mkBefore` for this purpose. The module
merge regression covers ordinary, earlier, and later caller additions.
[NixOS option definitions](https://nixos.org/manual/nixos/stable/#sec-option-definitions-merging).

Systemd `MemoryHigh` throttles and reclaims; `MemoryMax` is an OOM boundary.
Measure interval deltas in `memory.events`, `memory.pressure`, `cpu.stat`, and
swap usage. A high system-CPU fraction and repeated high-limit events indicate
reclaim, even if the process remains alive. Allow room for kernel metadata and
cache as well as the application heap.
[systemd resource controls](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html).

Go's `GOMEMLIMIT` is a soft runtime limit, not an RSS cap. Setting it below a
large live index can spend excessive CPU on collection. Keep a gap between the
Go target and the cgroup boundary, retain the hard ceiling, and validate actual
progress on the intended repository.
[Go garbage collector guide](https://go.dev/doc/gc-guide#Memory_limit).

Non-interactive Restic suppresses progress by default. `RESTIC_PROGRESS_FPS`
can enable infrequent updates, such as one per minute. JSON-lines status and
summary records expose counts, duration, errors, and the saved snapshot ID.
A restarted process is not a successful snapshot. Treat every nonzero exit as
unsuccessful; exit 3 means some source data could not be read.
[Restic progress reporting](https://restic.readthedocs.io/en/stable/manual_rest.html#progress-reporting),
[JSON output and exit codes](https://restic.readthedocs.io/en/stable/075_scripting.html).

Keep backup, repository pruning, and full integrity verification separate.
Retain repository locking and independent restore probes. Resuming an interrupted
backup reuses uploaded data; do not delete snapshots or unlock a live writer to
make a queue advance.
[Restic interruption FAQ](https://restic.readthedocs.io/en/stable/faq.html),
[repository maintenance](https://restic.readthedocs.io/en/stable/060_forget.html).

## Validation and limits

A live interval comparison reproduced reclaim under a memory threshold below
the working set and removed the high-limit events after increasing the budget.
A stale service override reapplied the smaller limit on daemon reload; inspect
both generated units and all drop-ins before relying on a changed assignment.
Keep raw paths, logs, and operational receipts outside the public repository.

Focused Restic round trips, queue serialization, module merging, and generated
policy checks are the verification entry points. Completion of a production
backup and its sample restore must be observed separately from these checks.

## Implication for this repository

Preserve composable exclusions, the shared bulk lock, encryption, and source
coverage. Keep the Go target below a measured cgroup budget, emit periodic JSON
progress, and allow bounded graceful interruption. Declarative units must own
the policy; remove obsolete manual overrides during activation.
