# Programming languages and compiler policy

Reviewed: 2026-09-11. Scope: current files in the root repository and its three
submodules, including pre-existing staged and unstaged changes. This extends the
[technology review](technology-stack-research.md) with language and compiler
choices.

## Answer

Keep the current language mix. The strongest migration candidate is the large
VM-control shell implementation, where Python can make structured parsing and
failure handling easier to review. Keep Rust for secret handling and filesystem
operations that must hold validated descriptors. Keep Swift for Apple framework
integration and small C interfaces where replacing them would retain the same
unsafe foreign calls.

The native programs already use substantial optimization and safety settings.
There is no evidence supporting global compiler overrides or a project-wide
rewrite. The initial assessment below distinguishes source observations from
proposed experiments. The implementation follow-up records the subsequently
verified fixes and bounded optimization measurements; it does not establish an
exploitable vulnerability or an application-level speedup.

## Implementation follow-up

The following changes implement the recommendations that have supporting evidence.
The inventory and initial assessment later in this note describe the source before
these changes.

| Component | Implemented change | Evidence |
| --- | --- | --- |
| Libvirt management | Move UUID preservation, disk-source selection, pool-path extraction and installer disk policy into a typed, bounded XML helper. Retain shell lifecycle and privilege boundaries. | 28 focused tests and four subtests pass on Linux and Darwin. The former table parser fails both running-domain cases with a disk path containing spaces; the replacement passes. |
| Steam CEF interposer | Run separate AddressSanitizer/UndefinedBehaviorSanitizer mocks; verify release ELF RELRO, immediate binding and a non-executable stack after fixup. | Native Linux Nix build passes release and instrumented scenarios. Mutated ELF fixtures missing each property fail. The installed library has no sanitizer runtime dependency. |
| Swift compiler wrapper | Repair the obsolete hardening-array reference, preserving cc-wrapper flag order. Apply the repaired compiler to the Darwin package scope and explicit local consumers. | An imported C header requires fortify and stack-protection macros: the actual original Nix wrapper fails and the repaired wrapper passes native typechecking, compilation and execution. OCR and Finder package builds also pass with the repaired compiler. |
| OCR Capture | Enable whole-module optimization for the direct release build. | Baseline and optimized fixture selftests pass with Swift 5.10.1 and 6.3.3; executable size decreases on both. |
| PersonalMonitor fan helper | Enable whole-module optimization for the helper; retain the full application's existing flags. | Baseline and optimized helper selftests pass with both compilers; executable size decreases on both. |
| PersonalMonitor concurrency | Enforce complete concurrency checking with warnings as errors for the Now Playing adapter; repair four helper diagnostics and add an explicit diagnostic command for all targets. | Adapter checks and helper selftests pass on the pinned compiler. Application errors and 19 helper warnings still require an isolation migration, so full checking remains an explicit diagnostic lane. |
| Secure-files Rust helper | Add installed-release checks for interrupted input and exec identity, status, signals and mapped-file preservation. Retain the release profile. | Native Darwin Nix build passes eight new cases, four existing filesystem tests, formatting and Clippy. Deliberately premature writes and temporary-file residue fail the new assertions. |

The [XML helper](../modules/nixos/virtualisation/scripts/libvirt-xml.py) uses
immutable disk records, rejects ambiguous targets and duplicate identity fields,
rejects DTD/entity declarations before parsing, and limits UTF-8 XML to 4 MiB.
It returns data to the existing controllers without launching subprocesses or
changing live state. XML serialization can normalize whitespace and discard
comments; tests compare libvirt semantics rather than spelling. Existing guest
identity checks, install confirmation and service transitions remain in the
shell callers. This is the first parsing/planning increment, not a rewrite of
the complete controllers.

The actual Linux NixOS modules also evaluate against the root pin with all
assertions passing under a fixture configuration. Seven generated script maps
pass strict substitution, Bash parsing and ShellCheck through the repository's
writer on Darwin. That rendering check substitutes only the native Bash
interpreter and strips dependency contexts from Linux command paths; it neither
builds the Linux closure nor executes the generated VM commands.

The [Swift repair](../overlays/temporary/swift-wrapper-hardening.nix) tracks
Nixpkgs revision `c5c4a43b0e8056328ec4529f735cabdb8f1942bb`. That wrapper reads
`hardeningCFlags`, while the associated cc-wrapper provides
`hardeningCFlagsBefore` and `hardeningCFlagsAfter`. The fix forwards both arrays
and fails on unexpected wrapper source. It runs inside `buildCommand`, because
this wrapper derivation does not execute ordinary phase hooks. The
[selection overlay](../overlays/packages.nix) explicitly supplies the repaired
compiler to OCR Capture, Finder Favorites and PersonalMonitor; Finder also sets
`SWIFT_EXEC` for SwiftPM. The temporary-fix registry requires review when the
input changes, and the Darwin check builds a native probe. This repair concerns
Clang flags passed through Swift; it does not imply that all prior Mach-O
hardening was absent. Both original and repaired probe executables had PIE, and
Finder's separately compiled C bridge already received stack protection.

### Optimization results and limits

The benchmark scripts compare the same source and compiler, alternating baseline
`-O` and `-O -whole-module-optimization` builds. These native arm64 macOS byte
counts precede Nix stripping and signing. Repeated OCR measurements use its legacy
recognition backend; the reusable script probes for the newer document backend.

| Target and compiler | Baseline bytes | WMO bytes | Change |
| --- | ---: | ---: | ---: |
| OCR, Swift 5.10.1 | 568,544 | 508,024 | −10.6% |
| OCR, Swift 6.3.3 | 523,024 | 464,104 | −11.3% |
| Fan helper, Swift 5.10.1 | 434,112 | 360,912 | −16.9% |
| Fan helper, Swift 6.3.3 | 402,512 | 342,272 | −15.0% |

For Swift 6.3.3, three-build median wall time fell from 6.35 to 4.28 seconds for
OCR and from 3.71 to 2.67 seconds for the helper. OCR build peak memory decreased;
helper build peak memory increased from approximately 201 to 246 MB. OCR warm
fixture selftest medians were approximately 5.9 versus 6.2 ms, so there is no
measured latency improvement to claim. These short process measurements are
not screen-recognition or fan-control benchmarks.

A single full-application Swift 6.3.3 comparison also produced a smaller binary
with WMO: 45,512,936 versus 41,614,976 bytes, with build time 362 versus 193
seconds. The package retains its existing application flags because this
comparison lacks pinned-compiler full-application and GUI runtime validation.
The reusable [OCR benchmark](../pkgs/pkgs/by-name/oc/ocr-capture/Scripts/benchmark-optimization.sh)
and [PersonalMonitor benchmark](../pkgs/pkgs/by-name/vo/vorssaint/Scripts/benchmark-optimization.sh)
document the inputs and optional application comparison. Neither launches the
GUI or accesses live screen content or fan controls.

The [concurrency diagnostic lane](../pkgs/pkgs/by-name/vo/vorssaint/Scripts/check-concurrency.sh)
continues checking the other targets after a compiler failure, then returns a
failure status. A [helper patch](../pkgs/pkgs/by-name/vo/vorssaint/fan-helper-concurrency.patch)
gives the controller its own logger with the same identity and reads startup
arguments through Foundation. These changes remove four pinned-compiler warnings;
the final patched helper is the source used for the measurements above.
Nineteen helper warnings remain, including queue captures and the imported
`mach_task_self_` global. The pinned application's initial check reports 366
warnings and 21 errors across 44 files before stopping, so those counts are lower
bounds. Adding `@MainActor` to its application delegate alone breaks ordinary
compilation at three callers; that incomplete change is excluded. Swift 6.3.3
additionally fails to produce a diagnostic for an expression in
`MenuPanelView.swift`. No new unchecked Sendable conformance or warning
suppression hides those results. Resolving the remaining actor-isolation findings
is unfinished work, requiring changes to the callers and shared state before
full checking can become a release gate.

The [release interruption checks](../tests/macos/check_secure_files_release.py)
terminate the actual installed Rust binary while it waits for the rest of stdin,
before temporary-file creation. They verify the original bytes, inode, mode and
directory contents. They do not prove cleanup after staging begins or during
`panic=abort`. Rust tests use a different panic profile, so no test-profile result
is presented as release unwind evidence. The existing `panic=abort`, overflow
checks, ThinLTO and single codegen unit remain appropriate to the current helper.

No benchmark established a need to replace the remaining Python orchestration
with Rust or Go. Native rewrites, global flags, forced Swift 6 mode and full-app
WMO remain conditional recommendations. All checks used fixtures and build
outputs; no system activation or live VM mutation was part of this work.

## Scope and language inventory

The inspected bases are root `7fd38c80a2aabdb16674fba7231496fa4a575bee`,
packages `e2f597a2fc77ff2551ac5612086cb57c5cb8e554`,
nix-seal `7f213a533ae7e626416de1e17c41f25bfc145674`, and
framework `11e4d9dfe816b9855ae9de8318734059d616d3a1`. Working changes mean those
commits alone do not reproduce the inspected source.

The inventory uses each repository's tracked paths and current file contents,
including staged additions, with deleted paths and documentation captures
excluded. It counts tests alongside production source. Embedded programs and
patches were inspected separately because extension counts miss them. This is a
language and build-policy review with focused source inspection, not a line-by-line
security audit or an inventory of every transitive application's implementation.

| Language | Local use | Recommendation |
| --- | --- | --- |
| Nix, 599 files | Host/home modules, package recipes, framework, test derivations | Keep. Another language would need to reproduce module evaluation, dependency declarations and platform composition. Improve evaluation structure and measure it before considering evaluator changes. |
| Python, 177 files | Maintenance, CI, fonts, browser checks, wallpaper, storage and VM helpers, site generation | Keep for orchestration and structured data. Consider native code only for a measured CPU or startup bottleneck, or a small filesystem operation with stronger ownership requirements. |
| Bash and POSIX shell, 65 `.sh` files and 19 `.sh.in` templates | Build phases, activation, service wrappers and operational CLIs; also extensionless session files and Nix strings | Keep short command wrappers. Move substantial state machines and multi-format parsing into Python incrementally. |
| Zsh | Embedded completion setup and interactive shell configuration | Keep for Zsh-specific behavior. Do not change login-shell contracts as an optimization experiment. |
| Nushell | Embedded structured shell configuration and integration hooks | Keep where the host application expects Nushell. It need not replace portable operational wrappers. |
| Rust, 29 files | nix-seal, local-control secure files, tests and fuzz targets; also upstream patches | Keep. This is the right place for secret ownership, typed policy and descriptor-bound operations. |
| Swift, 25 files | OCR Capture, Finder Favorites, native font test; Vorssaint source is fetched upstream | Keep Apple APIs native. Prefer incremental Swift language-mode and safety-check upgrades over Rust or Go ports. |
| C, six files, plus headers | Finder's CoreServices bridge, Steam CEF interposer, GTK CSS check and native test fixtures | Keep the small interoperability layers. Move new policy into existing safe-language callers; investigate removing manual ownership only when the native interface permits it. |
| C++, three `.cpp`/`.cc` files, plus headers and substantial patches | Native font tests, Noctalia policy tests, Crashpad regression; Hyprlock, Hypridle and Noctalia changes | Keep patches in upstream's language. A compositor or lock-screen replacement is a separate product and compatibility decision. |
| JavaScript, five `.mjs` files and embedded browser expressions | Browser protocol and rendered-UI tests | Keep. TypeScript could help if shared protocol models grow, but adds a checking/build layer and does not validate runtime responses. |
| Lua, two files and generated code | mpv integration, tests and Hyprland callbacks/configuration | Keep the host application's extension language. Extract expensive external work only after profiling. |
| PowerShell, one `.ps1` and two `.ps1.in` files | Windows bootstrap, baseline verification and analyzer driver | Keep native Windows management. Preserve the bootstrap's Windows PowerShell 5.1 compatibility requirement. |
| Awk and jq | Embedded table extraction and JSON transformations | Keep small expressions. Fold complicated transformations into the owning Python migration. |
| Perl | Two XML-rewrite expressions in libvirt setup; also an upstream resource in Vorssaint | Replace the local XML regexes with structured XML operations when revising VM setup. No reason to introduce a larger Perl application. |
| AppleScript | One macOS notification fallback invoked through `osascript` | Keep the tiny native adapter. Its strings are passed through environment variables rather than interpolated into AppleScript source. |

CSS, XML, HTML fragments, JSON, TOML, YAML, Caddy configuration, systemd policies
and Markdown are also present. They are configuration or presentation formats,
not candidates for a performance-driven programming-language migration. The
`justfile` files dispatch work in other languages. Editor support for TypeScript,
Go, C#, Java, Ruby or Typst does not establish an application written in those
languages here. Likewise, packaged desktop applications bring their own languages
and runtimes; rewriting a recipe does not rewrite its upstream application.
Patches also contain CMake and Meson build-language changes. Keep those in the
upstream build system rather than maintaining a replacement build definition.

Local anchors include the [framework](../nix-config-framework/README.md),
[Python policy](../pyproject.toml), [Bash writer](../lib/writers/bash.nix),
[Zsh configuration](../modules/home/shells/zsh/config.nix),
[Nushell integration](../modules/home/shells/nushell/extra-config-after.nix),
[JavaScript check](../flake/dev/javascript-checks.nix),
[Lua callbacks](../modules/home/desktop/workflow.nix),
[PowerShell writer](../lib/writers/powershell.nix), and
[notification adapter](../modules/home/dev/agentic-tui/scripts/opencode-notifier-darwin-fallback.sh).

## Where changing languages could help

### First candidate: VM-control shell to Python

The [Windows controller](../modules/nixos/virtualisation/scripts/libvirt-windows-vm-control.sh.in)
is 694 lines and the [workstation controller](../modules/nixos/virtualisation/scripts/libvirt-workstation-control.sh.in)
is 431 lines. They combine argument policy, state transitions, subprocesses,
formatted `virsh` output, XML queries and cleanup. The
[setup script](../modules/nixos/virtualisation/scripts/libvirt-workstation-setup.sh.in)
also inserts UUIDs into XML using Perl regexes.

Migrate parsing and planning first, preserving the CLI and privilege boundaries.
Use typed Python records, structured XML, explicit exceptions and argument lists
with `shell=False`. Domain XML exposes disk sources and targets directly, avoiding
reliance on display-column whitespace. An argument list avoids shell parsing; it
does not replace argument validation, allowlists or protection against option
injection. [libvirt domain XML](https://libvirt.org/formatdomain.html),
[Python subprocess rules](https://docs.python.org/3/library/subprocess.html#security-considerations).

Keep the existing protections during migration: guest and UUID checks, inactive
state requirements, restricted media inspection, immutable executable paths,
private temporary files, failure cleanup, and explicit destructive-operation
confirmation. Python's interpreter does not enforce any of these automatically.

The likely benefit is simpler review and fewer parser/process boundaries. A
startup or throughput improvement remains unmeasured; VM operations themselves
may dominate runtime. Start with XML identity preservation and disk selection,
then use the existing [VM setup fixtures](../tests/virtualisation/test_libvirt_workstation_setup.py)
and [seed-rendering tests](../tests/virtualisation/test_windows_seed_renderer.py).
Add cases for spaces in paths, malformed output, missing state, interruption and
repeated invocation before replacing the controller. No live VM should be needed
to test planning and parsing.

### Preserve Rust at the filesystem and secret boundaries

The [secure-files helper](../homes/macbook-pro-m4/local/local-control/secure-files-rs/src/lib.rs)
uses owned descriptors and relative `openat` operations. Existing shell adapters
already delegate their sensitive filesystem operations to it. The
[Python VM resolver](../homes/macbook-pro-m4/local/dev_vm_host.py) similarly uses
`dir_fd`, `O_NOFOLLOW` and descriptor validation. These are reasons to preserve the
existing behavior, not evidence that Python must be replaced.

If another helper needs a race-resistant file operation, place the complete
validation-and-use transaction behind a narrow interface. Merely translating
`stat(path)` followed by `open(path)` into Rust preserves the same race. A Rust
helper that validates a file then returns its pathname for a later reopen also
fails to preserve descriptor authority. Review ownership of every parent directory
and whether the consumer can use an already-open descriptor before choosing the
implementation.

Keep nix-seal in Rust. Its [crypto code](../nix-seal/crates/nix-seal-crypto/src/lib.rs)
already uses secret wrappers and zeroizing buffers. A Go or Python port would
require rebuilding those lifetime guarantees and interoperability tests, with no
identified performance benefit. Rust's unsafe-code ban covers this project's own
code; dependencies and operating-system interfaces still need scrutiny. Safe Rust
can rely on unsafe implementations underneath its interfaces.
[Rust safety boundary](https://doc.rust-lang.org/stable/nomicon/safe-unsafe-meaning.html).

### Keep Swift and constrain the remaining C

[OCR Capture](../pkgs/pkgs/by-name/oc/ocr-capture/Sources/OCRCapture/RecognitionBackends.swift)
uses Vision and other Apple frameworks. A Rust wrapper would still call those
frameworks and would add a foreign interface. It would not replace the OCR engine.

[Finder Favorites](../pkgs/pkgs/by-name/fi/finder-favorites/Sources/FinderFavoritesCore/Backend.swift)
already keeps planning and models in Swift. Its
[C bridge](../pkgs/pkgs/by-name/fi/finder-favorites/Sources/FinderFavoritesBridge/FinderFavoritesBridge.c)
owns Core Foundation objects and allocated strings for a deprecated native API.
Keep new policy in Swift. Consider reducing the bridge's owned string arrays only
if a prototype removes manual lifetime management without losing the required API
or Swift-toolchain compatibility. A Rust port that retains raw pointers and the
same API is not an established security improvement.

The [Steam interposer](../pkgs/pkgs/by-name/st/steam-cef-scale-override/steam-cef-scale-override.c)
is a small C ABI adapter using `dlsym`, bounded string handling and finite scale
validation. Keep it in C with its compiler diagnostics and fixtures. Removing the
interposer when upstream provides the needed behavior would remove more code and
risk than changing its implementation language.

### Keep Python until a benchmark identifies a reason to move

The [wallpaper fetcher](../modules/home/desktop/scripts/wallpaper-fetch-d2d.py)
calls curl and ImageMagick. The [backup helper](../hosts/nixos/desktop/local/storage/backup-helper.py)
calls external storage tools. Those are process and I/O boundaries, so a Rust port
of the orchestration alone does not establish faster image conversion or backup.
Preserve decoder limits, deadlines, private output handling and tests.

Two bounded performance experiments would be reasonable if users observe delay:

- Measure the [idle-inhibitor check](../modules/home/desktop/scripts/idle-inhibit-check.py)
  under the [five-second retry policy](../modules/home/desktop/idle.nix). Compare
  interpreter startup, `hyprctl` latency and JSON parsing separately. Keep the
  different screen-lock and suspend failure behavior in any native prototype.
- Measure the [Git privacy hook](../modules/home/dev/scripts/git-privacy-hook.py)
  on representative object counts and blob sizes. It already streams through
  `git cat-file --batch`; preserve that design. Consider a native scanner only if
  its matching loop, rather than Git or network requests, dominates the delay.

For either experiment, compare the same fixtures, warm and cold runs, wall time,
CPU time, peak memory and failures. Do not trade correctness or resource bounds
for a small throughput gain. Nix evaluation needs separate profiling because none
of these runtime language changes makes Nix module evaluation faster.

## Compiler settings and best practices

### Preserve Nixpkgs defaults rather than setting global flags

The [root lock](../flake.lock) selects Nixpkgs
`c5c4a43b0e8056328ec4529f735cabdb8f1942bb`; the standalone package, nix-seal and
development locks select `c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0`.
Root inputs can follow the root pin, so a standalone submodule build and an
integrated build need not use the same toolchain. The root also contains nested
Darwin pin `c19db427a1fdfc7591c0b0baeb4665dcef2c61da`; this does not mean every
Darwin derivation uses it.

The pinned defaults include fortification, format checks, stack protection,
position-independent code and applicable linker protections. Compiler and target
filters matter. For example, the pinned Clang configuration excludes fortify3
and Darwin stack-clash protection. ELF RELRO and immediate binding are not
Mach-O settings. Use the package's wrapped compiler and verify the resulting
commands instead of copying a generic flag list.
[Pinned defaults](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/build-support/bintools-wrapper/default.nix#L47),
[Clang support filters](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/development/compilers/llvm/common/clang/default.nix#L192).

The [GTK CSS checker](../lib/desktop/gtk-css-check.nix) illustrates why a source
search alone is insufficient. It has no explicit optimization flag, but its
wrapped C compiler adds `-O2` when fortification is enabled. There is no demonstrated
missing-optimization fix here. An explicit later optimization option can override
that default. [C hardening implementation](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/build-support/cc-wrapper/add-hardening.sh#L91).

### Rust settings are already appropriate

Both [nix-seal](../nix-seal/Cargo.toml) and
[secure-files](../homes/macbook-pro-m4/local/local-control/secure-files-rs/Cargo.toml)
use this release profile:

```toml
[profile.release]
lto = "thin"
codegen-units = 1
strip = "symbols"
overflow-checks = true
panic = "abort"
```

Keep overflow checks and the unsafe-code prohibition. Cargo's release optimization
level is already 3. ThinLTO and a single codegen unit are deliberate tradeoffs;
changing them needs measurements of runtime, build memory, build time and binary
size. More optimization is not automatically better. Cargo's stripping setting
also differs from the Nix build: the pinned build hook disables Cargo stripping
so stdenv handles it. [Cargo profiles](https://doc.rust-lang.org/cargo/reference/profiles.html),
[Nix build hook](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/build-support/rust/hooks/cargo-build-hook.sh#L8).

Retain the current panic policy pending an explicit cleanup review. Aborting
skips destructors, so it is not a universal security improvement for a program
with secret zeroization or terminal restoration. Prefer explicit errors and
checked arithmetic for expected failures.
[Rust abort behavior](https://doc.rust-lang.org/std/process/fn.abort.html).

There is a test-profile distinction in
[secure-files packaging](../homes/macbook-pro-m4/local/local-control/runtime-helpers.nix):
it builds release but replaces the default check phase with plain
`cargo test --all-targets`, which tests the development profile. However, the
[root Darwin checks](../flake/dev/local-control-checks.nix) already execute its
packaged release binary and adapters against malformed environments, denied
paths, duplicate credentials and symlinks. Preserve those checks. Extend release
coverage only for uncovered behavior, such as interruption and unexpected abort
cleanup, after mapping existing cases. nix-seal's Nix package already uses the
default release check profile. Even `cargo test --release` does not by
itself exercise abort-on-panic behavior because the test harness uses unwinding.
[buildRustPackage defaults](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/build-support/rust/build-rust-package/default.nix#L57),
[Cargo panic exception](https://doc.rust-lang.org/cargo/reference/profiles.html#panic).

### Swift: verify foreign-code flags and improve diagnostics

[Finder Favorites](../pkgs/pkgs/by-name/fi/finder-favorites/package.nix) uses
SwiftPM release builds, complete concurrency checks, warnings as errors and
extensive C diagnostics. [OCR Capture](../pkgs/pkgs/by-name/oc/ocr-capture/package.nix)
uses `-O` and the same concurrency policy, selecting Swift 6 mode when its compiler
supports it. Both already run an optimized selftest in their package recipes.
Their separate native quality scripts already include sanitizer coverage. Those
checks should not be proposed as new work.

There is a specific wrapper discrepancy worth reproducing on Darwin. The pinned
[Swift wrapper](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/development/compilers/swift/wrapper/wrapper.sh#L222)
forwards `hardeningCFlags`, but the
[C hardening script it sources](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/build-support/cc-wrapper/add-hardening.sh#L1)
defines `hardeningCFlagsBefore` and `hardeningCFlagsAfter`. The relevant files
match across the three inspected pins. This suggests computed flags can be
omitted on that forwarding path.

Capture native Darwin compile and link arguments before prescribing a repair.
Separately compiled C targets may use the ordinary C wrapper and receive its
flags. Swift's `-Xcc` options also concern its Clang interface, not Swift's own
optimizer. Therefore this discrepancy does not establish that Finder's bridge
or an installed Swift binary is unhardened. If reproduced, fix the wrapper
upstream or use a narrow documented override following the
[override lifecycle](../overlays/README.md). Verify relevant Mach-O properties
and runtime behavior after the change.

[Vorssaint](../pkgs/pkgs/by-name/vo/vorssaint/package.nix) has three
`swiftc -O -swift-version 5` commands without complete concurrency diagnostics.
Start a native diagnostic check with `-strict-concurrency=complete`, inspect its
existing `@unchecked Sendable` compatibility changes, fix warnings, then consider
warnings-as-errors and Swift 6 mode. Do not force the language mode solely because
a newer compiler exists. Finder already has a Swift 6 quality lane; OCR already
adapts its language mode. [Swift 5.10 checking](https://www.swift.org/blog/swift-5.10-released/),
[Swift migration guide](https://www.swift.org/migration/).

For OCR and Vorssaint's direct multi-file builds, benchmark
`-whole-module-optimization` as a package-local experiment. Retain it only with
useful latency or size improvement and acceptable build cost. Do not add
`-Ounchecked`, which removes runtime safety checks. Strict memory-safety checking
requires a suitable newer compiler; OCR already exercises it in its native
quality script and Finder documents its compatibility constraint.
[Swift optimization guidance](https://github.com/swiftlang/swift/blob/swift-5.10-RELEASE/docs/OptimizationTips.rst),
[Compiler option definitions](https://github.com/swiftlang/swift/blob/swift-5.10-RELEASE/include/swift/Option/Options.td),
[Swift 6.2 memory safety](https://www.swift.org/blog/swift-6.2-released/).

### C and C++: improve evidence around the existing flags

The [Steam CEF package](../pkgs/pkgs/by-name/st/steam-cef-scale-override/package.nix)
already uses `-O2`, `-fPIC`, hidden visibility, strict warnings, undefined-symbol
rejection, RELRO, immediate binding and a non-executable stack. Keep those
production settings. Extend its existing ELF inspection to assert GNU_RELRO,
NOW and a non-executable GNU_STACK, as applicable to this Linux shared library.
Its current checks assert architecture, SONAME and exports instead.

Add a separate mock-only sanitizer build for the shim and test executable:

```text
-O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined
-fno-sanitize-recover=all
```

Instrument both sides and link the sanitizer runtime into the executable. ASan
shared-library builds may need to omit `-Wl,-z,defs` and equivalent
undefined-symbol rejection in that test lane. Preserve production linking rules.
Run malformed scale values and initialization failures through the existing
fixtures. These flags are test instrumentation, not shipping hardening.
[Clang ASan](https://clang.llvm.org/docs/AddressSanitizer.html),
[Clang UBSan](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html).

Finder already has Clang warnings, static analysis, ASan and TSan in its
[quality script](../pkgs/pkgs/by-name/fi/finder-favorites/Scripts/check-quality.sh).
For compositor and greeter patches, retain upstream build policy and targeted
behavior tests. New global C++ flags could conflict with upstream's allocator,
linking or dependency choices. Review any inherited hardening exception on the
actual derivation rather than inferring its presence or absence from this
repository alone.

### Avoid blanket optimization or hardening switches

Do not set global `CFLAGS`, `CXXFLAGS` or `RUSTFLAGS`, disable hardening, force
`hardeningEnable = [ "all" ]`, or use `-Ounchecked` as a general policy. GCC's
`-fhardened` is GNU/Linux-specific and its expansion can change by compiler
release; it is not a cross-language substitute for the pinned Nixpkgs policy.
[GCC instrumentation options](https://gcc.gnu.org/onlinedocs/gcc/Instrumentation-Options.html).

Avoid `target-cpu=native` for shared/cacheable builds because it selects the
builder's CPU. Apply the same portability principle to C/C++ CPU targeting.
Use a separately named package variant and declared CPU baseline if measurements
justify host-specific optimization. PGO also needs representative training and
an independent correctness/performance comparison, not a global switch.
[rustc CPU options](https://doc.rust-lang.org/rustc/codegen-options/index.html#target-cpu).

Python, shell, Lua and PowerShell do not need project-level native compiler flags.
Use their existing type checks, linters and generated-script tests. A different
interpreter or JIT is a runtime compatibility change that needs its own workload
measurements. Third-party prebuilt applications cannot acquire native compiler
protections from flags added to their Nix unpacking or wrapping recipe.

## Recommended order and validation limits

1. Reproduce the Swift wrapper discrepancy on Darwin and inspect the actual C
   compile path. This is the strongest compiler-policy uncertainty.
2. Add CEF mock sanitizer coverage and release ELF assertions; map secure-files'
   existing release checks before extending interruption and cleanup coverage.
3. Migrate VM XML parsing and planning from shell/Awk/Perl to Python in small
   steps, retaining CLI and privilege contracts.
4. Introduce Vorssaint concurrency diagnostics and resolve findings before
   tightening language-mode requirements.
5. Benchmark direct Swift whole-module optimization or small native Python
   replacements only when there is a concrete latency or resource complaint.

The initial review inspected repository files and pinned Nixpkgs wrapper sources
and consulted primary documentation on 2026-09-11. It compared wrapper files
across pins but did not build applications, run sanitizers or audit Darwin
binaries. The implementation follow-up above records the later native checks
and measurements separately from that initial evidence.

The report was checked on Linux for Markdown, spelling, local links, whitespace
and publication-sensitive content. Further native checks need the relevant Linux
or Darwin host; heavy desktop checks must use `workstation-task` as documented in
the [testing guide](testing.md). No full host build or activation is claimed by
the focused package and fixture results.
