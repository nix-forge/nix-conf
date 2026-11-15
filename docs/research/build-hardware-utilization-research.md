# Build hardware utilization

Reviewed: 2026-10-12. Scope: Nix 2.34.9, systemd v261.2, current Cargo and
Ninja manuals, and Linux cgroup v2 documentation. This supplements the
[queue investigation](build-queue-efficiency-research.md) with resource sizing.

## Answer

For a desktop with 16 logical CPUs and about 30 GiB of memory, begin with one
local derivation and eight compiler jobs. Keep the existing 70% CPU ceiling and
lower scheduling weight for builds. Adjust memory limits from measured pressure,
with a fixed allowance for the interactive desktop. These numbers are a starting
policy, not a benchmark or a guarantee that every phase uses half the CPU.

Four compiler jobs cannot normally fill 16 logical CPUs. Increasing concurrent
derivations before identifying their memory requirements risks running several
large compiler or linker processes together. Preserve optimized release profiles
and correct native or cross platform selection.

## Findings and sources

### Separate derivation concurrency from compiler concurrency

Nix `max-jobs` controls simultaneous local derivations. `cores` supplies
`NIX_BUILD_CORES`; individual build scripts must honor it. Nix describes the
nominal concurrency as their product and warns against oversubscription.
One derivation with eight compiler jobs can expose more parallel work than one
with four, without admitting a second large derivation.
[Nix core and job settings](https://nix.dev/manual/nix/2.34/advanced-topics/cores-vs-jobs.html).

This is an inference about available concurrency. Dependency ordering, a large
single compilation unit, linking, downloads, and memory stalls can still leave
CPUs idle. Higher configured counts alone do not prove higher throughput.

### Preserve one concurrency budget through nested tools

Cargo and rustc coordinate through a jobserver. Build scripts inherit one slot
and should acquire additional slots when they perform parallel work.
[Cargo build scripts](https://doc.rust-lang.org/cargo/reference/build-scripts.html#jobserver).

Cargo defaults to the number of logical CPUs unless `--jobs` or `build.jobs`
sets another count. Ensure package hooks pass the intended bounded count.
[Cargo build command](https://doc.rust-lang.org/cargo/commands/cargo-build.html#miscellaneous-options).

Ninja 1.13 supports GNU Make jobserver coordination when no explicit `-j` is
provided and `MAKEFLAGS` describes a compatible jobserver. On POSIX it supports
the FIFO protocol, not the older pipe protocol. A nested Ninja invocation can
therefore require its own bounded count when its parent's jobserver is
incompatible. Check the actual invocation instead of assuming every tool shares
Cargo's budget.
[Ninja jobserver support](https://ninja-build.org/manual.html#_gnu_jobserver_support).

### Identify reclaim before increasing compiler jobs

The kernel throttles allocations above `memory.high` and forces reclaim.
`memory.max` can invoke the cgroup OOM killer. A conservative high limit can
therefore slow a compiler while the host still has available memory.
[Linux memory controller](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html#memory).

Compare interval deltas in the builder cgroup's `memory.events`, `cpu.stat`,
`memory.current`, and `memory.peak` with host available memory. Use
`memory.pressure` and host pressure to distinguish actual stalls from memory
occupancy. PSI reports time tasks wait for resources, including separate
partial and complete workload stalls.
[Linux pressure stall information](https://www.kernel.org/doc/html/latest/accounting/psi.html).

If reclaim stalls rise while the host has room, increase the daemon's memory
allowance before adding more compiler processes. On this machine class, a
10 GiB high boundary and 12 GiB hard limit are a bounded first adjustment from
6 GiB and 8 GiB. Alongside a separate 10 GiB user workload limit, the hard
ceilings total 22 GiB, leaving about 8 GiB outside those groups. This arithmetic
does not reserve memory for the desktop or account for unrelated services.
Check current host usage before applying it. The operations policy owns the
final values.

### Keep scheduling priority and a ceiling

Systemd CPU weights distribute time among competing sibling groups. Its CPU
quota uses one CPU as 100%, so 1120% permits 11.2 CPUs of time on a 16-thread
host. A low weight permits spare CPU use while yielding under contention.
Separate daemon and user groups have separate ceilings; these do not form one
shared total.
[systemd resource-control v261.2](https://github.com/systemd/systemd/blob/v261.2/man/systemd.resource-control.xml).

Keep these safeguards while increasing compiler parallelism. Do not raise the
quota merely because an eight-job compile phase remains below it.

### Preserve release quality and native execution

Cargo documents that more code generation units can reduce compile time but
produce slower code. LTO improves optimization at the cost of link time.
Incremental compilation retains data in the target directory for later builds.
An isolated fresh Nix build cannot assume that directory survives a previous
derivation. Changing these settings globally trades artifact quality or disk
work for an unmeasured compilation benefit.
[Cargo profiles](https://doc.rust-lang.org/cargo/reference/profiles.html).

Use native tools for the build platform and runtime checks only where the
build platform can execute the output's host platform. Cross compilation does
not make foreign runtime tests native. Remove forced emulator runners from
ordinary source builds and require a native target worker for their runtime
checks.
[Nixpkgs cross compilation](https://nixos.org/manual/nixpkgs/stable/#chap-cross).

## Validation and limits

This review read primary documentation. It ran no builds, evaluations, checks,
activation, or performance benchmarks. Resource recommendations require the
current live workload measurements and do not claim a measured speedup.

## Implication for this repository

Use one derivation with eight compiler jobs as the next default, retain CPU
headroom, and raise memory limits only with a host budget and pressure evidence.
Apply the same compiler budget to the shared launcher and future private
coordinators. Keep existing completed outputs. Change future job settings without
restarting successful or progressing compilations just to change their count.
The [desktop memory operations guide](../operations/desktop-memory-management.md)
owns queue admission and live resource changes.

## Productive compilation and repeated work

Reviewed: 2026-10-13. Scope: the package repository's Nixpkgs revision
`151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4` and current Cargo documentation.
This addendum examines source recipes and hook behavior, without executing
builds or tests. Live CPU and memory samples belong in private operational
evidence, not in a claim of measured speedup here.

### A second compilation can be a different profile

At the pinned revision, `buildRustPackage` defaults to `buildType = "release"`
and `checkType = buildType`. It exports those choices as `cargoBuildType` and
`cargoCheckType`. The application's explicit `checkType = "debug"` override
therefore creates a distinct check profile. The upstream default does not
require that override.
[Pinned buildRustPackage implementation](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/build-support/rust/build-rust-package/default.nix).

The check hook invokes `cargo test`, sets its build concurrency from
`NIX_BUILD_CORES`, and supplies the same count to `RUST_TEST_THREADS`. A check
type other than `debug` adds `--profile` explicitly. This hook performs tests,
despite its name, and is different from the Cargo `check` command.
[Pinned Cargo check hook](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/build-support/rust/hooks/cargo-check-hook.sh).

Cargo keeps artifacts in separate directories by profile and target. Debug
artifacts cannot simply replace optimized release artifacts. Matching the test
and build profiles can allow reuse of compatible dependencies within one
derivation. It does not remove compilation of test harnesses, extra test
dependencies, or artifacts with different features.
[Cargo build cache](https://doc.rust-lang.org/cargo/reference/build-cache.html).

Cargo tests compile special harness executables. A library may compile both as
a regular dependency and as a unit-test target. Cargo separates compilation
parallelism from runtime test threads; increasing `--jobs` alone does not bound
test execution. Explicit target selection controls coverage and is not merely
a speed setting.
[Cargo test behavior](https://doc.rust-lang.org/cargo/commands/cargo-test.html).

Changing the test profile is a correctness choice. Debug assertions and overflow
checking differ between profiles, and release LTO can make each test link
expensive. Preserve debug coverage when it is intentional. Where optimized
tests are the intended coverage, removing an unnecessary debug override follows
the Nixpkgs default, but its actual throughput benefit remains unmeasured.
Do not change installed release optimization settings to shorten tests.
[Cargo profile settings](https://doc.rust-lang.org/cargo/reference/profiles.html).

### Completed Nix outputs and Cargo intermediates are different caches

Nix runs each builder in a temporary directory and removes that directory after
the build. A recipe that installs binaries without exporting Cargo's intermediate
directory therefore does not create a reusable per-crate cache across distinct
derivations. Retaining the final output's GC root preserves the application,
not every intermediate object from its compilation.
[Nix builder execution](https://nix.dev/manual/nix/2.34/store/building.html).

A derivation describes its inputs, executable, arguments, and environment.
Changes to source paths, patches, features, profiles, or wrapper phases can
produce a different derivation even if the displayed application name is the
same. Record the derivation path and frozen source alongside each queue request
before calling two jobs duplicates.
[Nix derivation model](https://nix.dev/manual/nix/2.34/store/derivation/).

Normal `nix build` reuses matching realized outputs or substitutes them.
`--rebuild` deliberately rebuilds existing outputs for comparison. Avoid that
flag in ordinary package progress work, and reuse the same frozen recipe when
the requirements have not changed.
[Nix build](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-build.html).

### Fix repeated submissions before adding concurrency

Compare each request's derivation path, platform, requested phase, and prior
result. Join or reuse an existing request for the same immutable build instead
of appending another broad build-and-test submission. Retain distinct status
for skipped checks and completed checks. Do not report an omitted validation as
a pass.

Give each package or explicitly required check one queue turn. A coordinator
that enters the queue once and then loops over several builds retains the lock
for the entire loop. Queue admission should happen immediately before each
heavy invocation. This is a recommendation about the repository's exclusive
lock ownership, not a property of Cargo's jobserver.

When live samples show compiler activity without memory or I/O stalls, allow
the current build to finish. Adding more compiler jobs cannot remove profile
changes or repeated submissions. Remove forced duplicate check phases from
private launchers, keep normal package test semantics, and make optional broad
validation a separately requested task. No performance benchmark or check was
run for this addendum.
