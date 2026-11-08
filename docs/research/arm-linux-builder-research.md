# Desktop ARM Linux builder review

Reviewed: 2026-10-09. Scope: desktop ARM64 package builds using QEMU user-mode
11.1.1 and NixOS binfmt integration. Module references below use the compatible
26.05 Intel testing pin `c5c4a43b0e8056328ec4529f735cabdb8f1942bb`;
individual package flakes may use another revision. Inspect the instantiated
derivation before attributing hook behavior to a particular package build.

## Current recommendation

Use the desktop's native x86-64 tools to cross-compile ARM Linux packages and
retain QEMU user-mode for executing target programs and focused tests. A native
ARM Linux worker is preferable for native build validation and packages without
cross support. An emulated ARM VM adds overhead and has no ARM KVM acceleration
on this x86 host. The dated review below explains the current policy; the
2026-10-09 compiler-under-emulation advice is historical.

## Historical 2026-10-09 answer

The installed builder uses the supported NixOS setup correctly. Keep binfmt
user-mode execution for desktop ARM package builds. It needs no resident guest,
VM CPU assignment, or emulator restart. Run Linux builds on the desktop and
Darwin builds on the Mac.

The applied improvement is explicit build dispatch: `just arm-build PACKAGE`
and `just arm-check CHECK` require the desktop, select ARM Linux outputs, disable
remote builders for that invocation, and enter the workload queue with one
local derivation and four compiler jobs. Invoke independent packages separately
so the queue can serve other waiting work between them. This uses the existing
four-core host budget without increasing simultaneous derivations or memory
limits. It requires no system activation.

## Findings and sources

The pinned NixOS binfmt module adds the emulated system to Nix's supported
platforms and mounts the interpreter dependencies in build sandboxes. Its QEMU
rule preserves argv zero and uses a compiled native wrapper without an extra
shell process. The live registration is enabled and uses the `P` flag. The
wrapper forwards guest loader variables while removing them from the native
emulator's environment. Retain this upstream integration rather than replacing
it with a direct dynamic-QEMU rule.
[Pinned binfmt module](https://raw.githubusercontent.com/NixOS/nixpkgs/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/nixos/modules/system/boot/binfmt.nix),
[pinned argv wrapper](https://raw.githubusercontent.com/NixOS/nixpkgs/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/by-name/qe/qemu/binfmt-p-wrapper.c).

QEMU user-mode translates guest system calls and creates host threads for guest
threads. It does not have a VM vCPU allocation. System-mode `-smp` and MTTCG
accelerator flags do not apply to this builder. Its translation cache is already
bounded for workloads with many emulator processes; no measured cache-flush
bottleneck supports increasing it here.
[QEMU user-mode documentation](https://www.qemu.org/docs/master/user/main.html),
[QEMU 11.1.1 translation memory](https://raw.githubusercontent.com/qemu/qemu/v11.1.1/tcg/region.c).

Static emulators and the kernel's `F` flag are supported when interpreters must
remain available across chroots without path mounts. The existing Nix sandbox
integration and tested namespace execution work. There is no evidence that a
static switch would improve compilation speed, so the default remains intact.
[Kernel binfmt flags](https://docs.kernel.org/admin-guide/binfmt-misc.html).

Nix's derivation concurrency and per-build core settings are separate. Pinned
Cargo hooks pass the per-build core count to both compilation and test-thread
limits. A four-job trial can use idle CPU capacity within the existing budget;
its speedup is not established by configuration inspection.
[Nix core and job guidance](https://nix.dev/manual/nix/2.28/advanced-topics/cores-vs-jobs.html),
[pinned Cargo check hook](https://raw.githubusercontent.com/NixOS/nixpkgs/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/build-support/rust/hooks/cargo-check-hook.sh).

## Validation and limits

Live checks confirmed an enabled ARM interpreter, ARM `uname` output, and ARM
execution inside a separate user and mount namespace. The active build uses
QEMU user-mode and continues compiling successfully. A probe inside its actual
Nix sandbox also reported `aarch64`. An initial probe selected an ARM binary
outside that sandbox's inputs and was rejected; using its declared coreutils
input succeeded, consistent with the sandbox's restricted store view.
Its memory cgroup was
below the configured pressure threshold and reported zero current memory
pressure. Historical limit-event counters do not establish current throttling.
The daemon retains its existing memory, swap and sandbox policies.

Five focused tests passed. They exercise the new commands' desktop-only guard,
ARM output selection, single queue dispatch, local builder selection and exit
status propagation, plus the existing system-build recipe regression. Ruff and
format checks passed. These dispatch tests use controlled command adapters;
they do not claim a new ARM source build or four-core performance benchmark.

No full-system rebuild, activation or binfmt reload was needed. The replacement
per-package matrix uses four compiler jobs; a later live observation found four
CPU-bound ARM compiler processes and continuing compilation. This establishes
usage, not a measured speedup. Completed outputs and debug-profile test coverage
remain intact.

## Follow-up workflow review

Long monitoring calls can delay chat updates independently of compiler progress.
The reviewed helper waited roughly 37 minutes per invocation. A replacement
returns within 60 seconds, retains log offsets between calls, handles rotation
and truncation, and reports phase changes, completion and errors. It uses a
separate lock to prevent concurrent monitors from overwriting their offsets.

Matrix durations include shared-queue waiting and must not be reported as pure
compile time. Historical failed rows remain historical evidence after a recipe
is corrected and passes a separate retry. Final verification must identify the
current derivations and outputs rather than treat the old failure flag as proof
that the current source still fails.

The task-local final verification helper archives the flake and its inputs once,
retains those source paths, and checks the fixed store snapshot. Each target
enters the shared queue separately with the desktop-only four-core policy. It
records derivation paths, output paths and elapsed time including queue wait.
The aggregate GUI check depends on current checks; earlier failed rows do not
suppress it. Ordinary builds reuse matching outputs and omit `--rebuild`.
[Nix flake archive](https://nix.dev/manual/nix/2.28/command-ref/new-cli/nix3-flake-archive.html),
[Nix build results and rebuild behavior](https://nix.dev/manual/nix/2.28/command-ref/new-cli/nix3-build.html).

Seven controlled helper tests passed, covering fixed-snapshot dispatch, historical
and current failures, cancellation, desktop and active-matrix guards, partial log
lines, rotation, truncation and persistent offsets. These tests exercise workflow
behavior; final package verification remains the owning task's queued work.

## Build throughput and desktop responsiveness review

Reviewed: 2026-10-11. This follow-up compares native desktop cross-compilation,
Cargo profile changes and resource-policy tuning. It recommends a pilot; it does
not change active builds or claim a measured improvement.

### Recommendation

Introduce an opt-in ARM package variant whose compiler and build tools execute
natively on x86-64 Linux. Keep the upstream optimized release profile initially.
Use QEMU for the resulting ARM tests and smoke checks, with explicit evidence
that those checks executed. Retain the existing emulated-native package path
until the variant passes equivalent validation.

Nixpkgs distinguishes the platform running the build tools from the platform
running the resulting application. Cross-compilation can therefore remove
emulation from compiler execution while still producing ARM executables. This
is the strongest candidate for this workload, based on the observed emulated
compiler and expensive optimization phase. Its local speedup is unmeasured.
[Nix cross-compilation tutorial](https://nix.dev/tutorials/cross-compilation.html).

### Observations and constraints

The workstation has eight physical CPU cores and sixteen logical CPUs. A short
live sample found 18.1% total CPU utilization, 12.2% attributed to Nix builders,
and 14.5 GiB available RAM out of 30.2 GiB. Builder memory was approximately
2.3 GiB, below the 6 GiB pressure threshold and 8 GiB maximum. Neither the daemon
nor the host showed recent memory pressure, and the daemon had no CPU quota
throttling. These observations cover one compilation stage, not peak usage
across the matrix. Idle logical CPUs do not imply proportional unused physical
CPU throughput because simultaneous multithreading shares execution resources.

The current host configuration selects one derivation and two compiler jobs. Its
comment records earlier RAM exhaustion and two large builders exceeding the
daemon's pressure threshold. Preserve that default while measuring an opt-in
variant. The active compiler uses optimization level three, thin LTO and one
code-generation unit. Increasing Cargo jobs does not split that unit.

Cargo documents that more code-generation units can improve parallelism and
compile time at a potential runtime performance cost. Thin LTO is already a
less costly alternative to fat LTO. Preserve these upstream choices for the
initial cross-compilation comparison; test profile changes separately if needed.
[Cargo profile settings](https://doc.rust-lang.org/cargo/reference/profiles.html).

### Preserve checks explicitly

At the package flake's Nixpkgs revision
`151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4`, the generic derivation constructor gates
ordinary check and install-check phases on whether the build platform can
execute the host platform. Setting `doCheck = true` alone therefore does not
prove that ARM tests execute during an x86 cross-build.
[Pinned check-phase gating](https://raw.githubusercontent.com/NixOS/nixpkgs/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/stdenv/generic/make-derivation.nix).

Use an explicit test build phase or a separate validation derivation running
native build tools and ARM test executables through a configured runner. Cargo's
target runner applies to test, run and benchmark executables. Preserve debug
assertions, existing library-test selection, required fixtures, CLI checks and
graphical smoke checks. Record test counts and verify the ARM interpreter and
libraries inside the sandbox. Emulated tests do not establish native ARM
real-time performance.
[Cargo target runners](https://doc.rust-lang.org/cargo/reference/config.html#targettriplerunner).

Build-time programs, procedural macros and generators must run on x86-64; linked
native libraries and runtime dependencies must target ARM. Audit target linker,
pkg-config and generated assets before enabling a cross variant. Cross and
emulated-native derivations have different identities, so their output caches
are not interchangeable. A first cross build may spend substantial time building
its new toolchain and dependencies. Separate this setup cost from steady-state
package measurements.

### Resource policy and acceptance

Keep one large derivation at a time and the existing memory ceilings. For the
pilot, start with four compiler jobs and test six or eight only if full-run memory
and pressure measurements support them. Retain the lower CPU and I/O priorities
for background work. A target of 50-70% CPU use is a preference during parallel
stages, not a required utilization floor or a guarantee from the job count.
[Nix core and job guidance](https://nix.dev/manual/nix/2.35/advanced-topics/cores-vs-jobs.html).

Systemd CPU weights distribute capacity under contention; they do not impose a
percentage ceiling. A quota is expressed relative to one logical CPU, so 960%
corresponds to 60% of sixteen logical CPUs. If a hard background ceiling is
needed, account for both daemon builders and separately grouped user-side
evaluation. Applying the same ceiling independently to both does not create an
aggregate ceiling. Do not add quotas to an already underused compilation stage.
Use memory-high as the normal pressure control and memory-max as the final
containment boundary; neither reserves physical RAM for desktop applications.
[Systemd resource control](https://github.com/systemd/systemd/blob/v261.2/man/systemd.resource-control.xml).

Compare a fixed source and dependency snapshot using the same features, release
profile and test scope. Record queue waiting separately from execution, actual
compiler CPU time, cgroup peak memory, pressure events and desktop responsiveness
under the usual interactive workload. Validate the ARM binary architecture,
installed runtime closure and test outputs. A tiny package can establish the
toolchain path; a representative large application must establish throughput
and memory behavior before rolling out the change. Do not force full matrix
rebuilds or discard completed output roots to obtain measurements.

This follow-up ran read-only configuration, process and resource inspection and
reviewed primary documentation and pinned source. No cross-compilation build,
profile benchmark, resource-policy activation or throughput experiment ran.

### Initial pilot implementation

The package repository now exports opt-in CADCraft and PhotoCraft cross variants,
with explicit Cargo library-test and installation-check phases, ARM ELF output
verification, and aggregate CLI and graphical checks. Ordinary package outputs
retain their existing compiler path. The workstation exposes `arm-cross-build`,
`arm-cross-check` and a small `arm-cross-toolchain` integration command. Dispatch
uses one derivation, no remote builders and four jobs by default. Only explicit
four-, six- and eight-job choices are accepted. Existing memory limits remain.

Focused dispatch and ELF rejection tests passed. Evaluation confirmed x86-64
builder systems, explicit test phases and CLI dependencies on the cross variants.
The isolated pilot's and final integrated package checkout's all-system no-build
flake checks passed. All four pilot checks evaluated successfully. Evaluation
on Darwin disabled import-from-derivation, so it performed no Linux compilation.
Actual toolchain compilation is queued on the desktop behind the active package
work. Full application compilation, ARM runtime checks and performance
measurements remain pending; the pilot is not promoted to the default path.
See the package repository's `docs/arm-cross-builds.md` for the validation contract
and measurement procedure.

### Completed pilot and default workflow

Reviewed: 2026-10-12. The toolchain proof and CADCraft, PhotoCraft and VectorCraft
aggregate cross checks passed, including ARM library tests, installation checks,
ELF verification, CLI rendering and software-rendered X11 startup. Follow-up
checks against the integrated package recipes also passed for all three apps.
The workstation's standard `arm-build` and `arm-check` commands now select these
cross variants, including their CLI and GUI check aliases. Other applications
retain their existing dispatch until individually validated.

Keep one derivation per queue turn and four compiler jobs. PhotoCraft reached
the existing memory-high reclaim threshold without an OOM, so the completed
pilot does not justify increasing concurrency or memory limits. The daemon's
desktop CPU ceiling and its generated resource policy were also verified.
Compilation remains on the Linux desktop. The completed checks establish build
and runtime correctness for the tested variants; they do not establish a
controlled speedup comparison or replace native physical ARM graphics testing.

### Repository-wide default

Reviewed: 2026-10-12. The owner requested applying cross compilation to every
ARM package and project repository without additional validation runs. Ordinary
`aarch64-linux` exports now use x86-64 Linux build tools in the package repository,
root project, framework, nix-seal and nix-homelab. The framework also applies the
ARM build platform to NixOS and standalone Home Manager targets. Native developer
tools come from `buildPackages`; ARM CI jobs use x86-64 workers with target
execution support. Native Linux and Darwin targets retain their own platforms.

The per-package dispatcher, experimental suffixes, pilot module and dedicated
pilot-check commands were removed. `just arm-build PACKAGE [REPOSITORY]` is the
single desktop entry point, preserving the workload queue and resource limits.
No additional build or validation jobs were run for this change at the owner's
request. Upstream cross-compilation support remains a package requirement; there
is no automatic return to emulated compiler builds. See the package repository's
`docs/arm-cross-builds.md` for current commands and platform boundaries.

### Native-first correction

The owner clarified that native compilation must take priority when build and
host architectures match. The preceding forced-x86 policy is superseded.
Ordinary package outputs and CI workers are native again. Each project repository
exports `lib.packagesFor` for explicit build/host platform pairs; the workstation's
`linux-build` command selects the actual build platform and crosses only when
needed. Both ARM-to-x86 and x86-to-ARM Linux are supported by that selector.
The `arm-build` command is a convenience entry to the same implementation.

Framework targets are native by default, with explicit `buildSystem` support
for cross NixOS or Home Manager configurations. Pi deployment selects the desktop
architecture. Binfmt registration selects the opposite architecture, so native
programs do not get an emulator for their own CPU. Cross-compilation itself uses
native compiler tools; emulation is only for target program execution. No new
builds or validations were run for this correction.

## Setup review on 2026-10-15

Reviewed: 2026-10-15. Scope: Nix builds of ARM64 Linux applications from an
x86-64 Linux desktop. Official documentation was retrieved on this date;
NixOS implementation references use the root flake’s actual Nixpkgs input
`7fd4004d0511991fff3a0524856a9be09e28c5f0` (the root lock edge selects
`nixpkgs_4`, rather than the separately named nested Intel testing input). This is an addition to the existing
ARM builder research, preserving its dated observations. Its original
2026-10-09 recommendation to run compilers under emulation is historical;
the later native-first correction and the recommendation below supersede it.

### Answer

For the existing desktop, retain **native x86-64 compilation targeting ARM Linux,
with QEMU user-mode only where ARM programs must execute**. That is already the
purpose of the repository's `just arm-build` selector. Keep ordinary ARM flake
outputs native so a real ARM Linux builder can build them without changing their
meaning. Do not introduce a resident emulated ARM VM as a compilation
optimization. This is a recommendation based on architecture and existing local
validation, not a new measured performance comparison.

A sufficiently capable native ARM Linux builder is a useful addition for native
package validation, packages that cannot cross-compile, and sustained ARM work.
Nix supports SSH builders with declared platforms. It does not require a
particular cloud service or new physical machine. Whether such a builder is
faster or worth its operating cost depends on its CPU, RAM, network and workload;
none was benchmarked here. Linux work remains on Linux; the Mac is excluded by
the project's placement policy.
[Official Nix remote-build manual](https://nix.dev/manual/nix/2.35/advanced-topics/distributed-builds.html).

### Findings and sources

#### Choose the execution model explicitly

| Model | Appropriate use | Main limitation |
| --- | --- | --- |
| Native ARM Linux machine or ARM-hosted Linux VM | Native package builds and ARM kernel/runtime verification | Requires an ARM Linux worker with sufficient resources |
| x86-64 compiler producing ARM output, with QEMU target execution | Existing desktop workflow; efficient use of its native build tools | Package and dependency build scripts must support cross compilation |
| ARM-native derivations running under x86-64 binfmt emulation | Compatibility fallback or controlled diagnosis | Also emulates compilers and build tools; do not advertise this as the default worker |
| Full ARM system emulation on x86-64 | ARM guest-kernel, boot and system integration tests | Adds guest-kernel/device emulation; provides no ARM KVM acceleration on this host |

Nixpkgs separates the build platform, which runs build tools, from the host
platform, which runs the result. The third, target platform principally matters
when building compilers. `localSystem = "x86_64-linux"` with an AArch64
`crossSystem` retains native compilers while selecting ARM libraries. The official
cache has limited cross output coverage; package support is not universal.
[Official cross-compilation tutorial](https://nix.dev/tutorials/cross-compilation.html).

QEMU user-mode translates guest instructions and Linux system calls against the
host kernel. Guest threads become host threads; there is no VM vCPU allocation
for this setup. It has documented syscall, namespace and memory-model limits,
so a passing emulated test does not establish physical ARM graphics, timing or
kernel behavior. This is a reason to retain native ARM validation where that
behavior matters, not to disable tests generally.
[QEMU user-mode documentation](https://www.qemu.org/docs/master/user/main.html).

Full-system QEMU instead supplies a guest machine and guest OS. The ARM `virt`
board documents KVM execution on **AArch64 hardware**. An x86-64 desktop cannot
turn that ARM guest into a hardware-accelerated ARM machine by adding `-enable-kvm`
or more `-smp` CPUs; it needs TCG for the foreign CPU. A Linux VM on ARM hardware
is a different option from full ARM emulation on this desktop.
[QEMU system introduction](https://www.qemu.org/docs/master/system/introduction.html),
[QEMU ARM virt platform](https://www.qemu.org/docs/master/system/arm/virt.html).

#### Keep cross dependencies and tests honest

Use `callPackage` and the Nixpkgs dependency roles rather than a global compiler
replacement. Programs needed during the build belong in `nativeBuildInputs`;
libraries linked into ARM outputs belong in `buildInputs`. Let the spliced
package set select the appropriate variant; use `buildPackages` explicitly where
a native tool must be selected outside that mechanism. Enable `strictDeps` and
audit generators, pkg-config, native dependencies and target linker selection.
[Nixpkgs dependency categories](https://nixos.org/manual/nixpkgs/stable/#ssec-cross-dependency-categorization),
[pinned cross-compilation implementation guide](https://raw.githubusercontent.com/NixOS/nixpkgs/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/doc/stdenv/cross-compilation.chapter.md).

Rust build scripts execute on the build machine. Target decisions in `build.rs`
must use Cargo's target configuration variables, rather than `cfg!`, which
reflects the build-script executable. Audit native procedural macros and
code-generation executables separately from ARM linked libraries.
[Cargo build scripts](https://doc.rust-lang.org/cargo/reference/build-scripts.html).

Compilation success alone does not prove tests ran. Pinned Nixpkgs gates ordinary
check phases on `buildPlatform.canExecute hostPlatform`; `doCheck = true` by
itself cannot override that platform decision. Inspect the actual derivation and
hooks for the package's own pin. Use an explicit test phase or a separate focused
validation derivation for cross tests. A Cargo target runner applies to `run`,
`test` and `bench`; it can invoke QEMU explicitly, or an available binfmt handler
can execute the target directly. Record the exact test names and nonzero test
counts, executable architecture, source revision, interpreter version and
features. Do not accept a successful zero-test filter as regression evidence.
[Pinned stdenv check gating](https://raw.githubusercontent.com/NixOS/nixpkgs/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/stdenv/generic/make-derivation.nix),
[Cargo target runner](https://doc.rust-lang.org/cargo/reference/config.html#targettriplerunner).

#### Preserve sandbox integration and dispatch boundaries

The pinned NixOS module supplies a compiled QEMU `P`-flag wrapper, interpreter
sandbox paths and the interpreter dependency closure. Preserve that integration
when updating QEMU. Its `addEmulatedSystemsToNixSandbox` option gates both
`extra-platforms` and `extra-sandbox-paths`. Setting it false without replacing
those paths would break dynamic-emulator execution in sandboxes. The existing
host instead retains the integration and forces `extra-platforms` to native
compatibility platforms, preventing automatic ARM compiler scheduling.
[Pinned binfmt module](https://raw.githubusercontent.com/NixOS/nixpkgs/7fd4004d0511991fff3a0524856a9be09e28c5f0/nixos/modules/system/boot/binfmt.nix).

The wrapper translates the preserved original argv-zero and forwards guest
`LD_*` settings without loading them into the native QEMU process. A bare dynamic
QEMU registration is therefore not an equivalent substitution. A static emulator
with the kernel's `F` flag is another supported design, but it is not established
as a compilation-speed improvement. No switch is justified for that purpose.
[Pinned QEMU wrapper](https://raw.githubusercontent.com/NixOS/nixpkgs/7fd4004d0511991fff3a0524856a9be09e28c5f0/pkgs/by-name/qe/qemu/binfmt-p-wrapper.c),
[kernel binfmt flags](https://docs.kernel.org/admin-guide/binfmt-misc.html).

Retain `sandbox = true`. Declare ARM test libraries and fixtures, and ensure the
registered emulator and its closure are visible inside the build sandbox. Do not
bind a user's whole store or home directory into it to repair undeclared inputs.
Keep signature verification enabled and trust only deliberately chosen cache
keys. Cross and native outputs have different derivations; adding a native ARM
cache does not guarantee a hit for cross-built packages. A project cache can
reuse successful cross outputs with their exact inputs.
[Nix sandbox and cache settings](https://nix.dev/manual/nix/2.35/command-ref/conf-file.html),
[Nix cross cache guidance](https://nix.dev/tutorials/cross-compilation.html#next-steps).

Keep one large derivation per desktop queue turn. `max-jobs` limits concurrent
Nix builds, while `cores` is the budget exposed to each build; packages may use
it differently. The current local workflow uses the configured compiler budget
and existing memory limits. The older four-job advice in this note is historical;
the current operations guide records an eight-job default. Change that only
with observed peak memory and responsiveness evidence, not because QEMU exposes
many host threads. Preserve source/output roots for valid cache reuse.
[Nix cores versus jobs](https://nix.dev/manual/nix/2.35/advanced-topics/cores-vs-jobs.html).

### Validation and limits

This research inspected the repository's current selector, package factory,
platform import policy and desktop binfmt configuration. It ran no builds,
resource benchmarks, VM or remote-builder provisioning, and made no configuration
changes. Prior package pilot results in the dated sections remain valid for their
recorded inputs and scope; they are not a new build matrix.

The separate EffectCraft investigation previously demonstrated that the same
unpatched ARM test executable failed under QEMU 11.1.1 and passed under 11.1.2.
That result diagnoses an emulator regression, not universal correctness of every
package on the new interpreter. The current task must separately identify the
registered interpreter after activation and run the focused test against the
currently selected EffectCraft source without the temporal patch. Record that
result and its sandbox status separately; do not infer it from the older binary
or from an explicit-QEMU invocation alone.

### Implication for this repository

Retain the native-first `lib.packagesFor { buildSystem; hostSystem; }` contract
and the queued `just arm-build PACKAGE [REPOSITORY]` command. It already selects
x86-64 cross tools when invoked on the desktop for ARM Linux and refuses Darwin
build machines. Ordinary `packages.aarch64-linux` exports still describe native
ARM builds. A future native ARM Linux worker should receive those native
outputs explicitly; the desktop helper currently disables remote builders for
its own selected local cross job.

The actual root Nixpkgs input provides QEMU 11.1.1. A narrowly scoped
backport of the upstream QEMU 11.1.2 version and source hash for the registered
user-mode interpreter, with its existing binfmt wrapper, is the fix now. It
does not require updating the global Nixpkgs pin or the separate system-mode
QEMU package used for native VMs.
Do not add an emulated ARM compiler worker or resident full-system guest. A
native ARM Linux builder is an optional follow-up for wider native validation;
there is no evidence here that it is necessary to complete the focused
EffectCraft regression check.

## Configured interpreter update and validation (2026-10-15)

The scoped QEMU user-mode 11.1.2 backport is now active on the x86-64 desktop
and installed as its default boot generation. The interpreter and compiled P
wrapper came from the trusted Nix cache; only fourteen small NixOS configuration
derivations were built. Inspection confirmed that system-mode QEMU, kernel,
initrd, application outputs and unrelated services were unchanged. No reboot
was performed. The normal binfmt registration and restarted Nix daemon use the
new wrapper and its dependency closure, retaining `sandbox = true`,
`sandbox-fallback = false` and only `i686-linux` as an extra compatibility
platform.

The unchanged effects-crate regression from selected EffectCraft
[`05955c08`](https://github.com/storytold/effectcraft/commit/05955c08b4fd025f1a09882df72e6dbff1a8148a)
was compiled with optimization level 3, debug assertions and explicit overflow
checks. The retained dependency identities and checksums match its upstream
lock. Native x86-64 passed. The identical ARM executable failed with the original
multiplication overflow under QEMU 11.1.1 and passed under 11.1.2.

After activation, the frozen ARM executable also passed through registered
binfmt inside a Nix derivation with strict sandboxing and fallback disabled:
exactly one test passed, zero failed. The derivation declares the executable
and its ARM library closures; emulation comes from the daemon's default sandbox
paths. It adds no custom interpreter path or broader host store binding. This
satisfies the temporal-offset workaround's retirement condition.

This is a focused effects-crate regression check. Its compilation was performed
separately; the Nix sandbox receipt proves test execution, not sandboxed
compilation, a full application build or the complete workspace suite. Native
ARM hardware and a fresh all-platform package build matrix remain untested by
this task. The recommended native cross-compilers with QEMU target execution
remain appropriate; a native ARM Linux worker is a separate validation option.
