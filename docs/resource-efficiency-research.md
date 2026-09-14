# Project resource-efficiency research

Reviewed: 2026-09-11. Scope: root-owned Nix configuration, build/check inputs,
CI, desktop background work, storage, and Python file processing. Root base is
`7fd38c80a2aabdb16674fba7231496fa4a575bee`; extensive existing working changes
are part of the inspected baseline. Existing changes are distinguished from improvements implemented in this review.

## Answer

This review reduced file allocations, preference rewrites and unnecessary CI
evaluation. File hashing, CRX extraction and wallpaper candidate filtering use
bounded buffers. Spotify preferences use one pass and preserve unchanged files.
CI selects relevant names before evaluating derivations, and wallpaper preference
edits reject invalid settings before writing. Existing host resource policies
remain in place.

Most broad resource controls are already present: bounded desktop build and
evaluator concurrency, a queued workload cgroup, compressed swap, low-cost
filesystem compression, cache selection, filtered check sources, and development
flake partitions. The earlier [desktop review](desktop-performance-research.md)
and [cache review](nix-caches-research.md) explain those choices.
Preserve them unless a controlled comparison identifies a regression.

## Versions and evidence

The installed CLI reports Determinate Nix 3.22.3 with Nix 2.35.2. The research
shell's Python is 3.14.7. The root lock pins nixpkgs to
`c5c4a43b0e8056328ec4529f735cabdb8f1942bb`, Determinate integration to
`cb76ac22754f6b36c008a3c39477c174a146dd6b`, and flake-parts to
`31729ca8cbdb4fa927b34e5f4353e6a83f39e993`.

The previous desktop note records systemd 261.2 and Linux 7.2.3. This research
pass did not independently query the running kernel or system manager. Systemd
claims below use the versioned 261.2 source. Other upstream documents were
retrieved on the review date; moving manuals describe upstream behavior, not
proof of installed runtime behavior.

## Implemented changes

### Stream evidence and wallpaper hashing

[The evidence recorder](../scripts/workstation_evidence.py) now hashes each tracked
file through `hashlib.file_digest()` and reuses the digest for lockfile metadata.
[The astronomy fetcher](../modules/home/desktop/scripts/wallpaper-fetch-d2d.py)
uses the same API for the rendered image checksum. Both previously allocated
whole-file bytes. SHA-256 and the serialized source-identity format remain
unchanged. The recorder still reads every tracked file and stores its inventory;
this change bounds the file-content buffer rather than caching mutable inputs.

Python requires a blocking binary stream and callers must close it afterwards.
CPython 3.14.7 uses a reusable 256 KiB buffer for ordinary files. Each call here
opens its own file with a context manager.
[Python API](https://docs.python.org/3.14/library/hashlib.html#hashlib.file_digest),
[CPython implementation](https://github.com/python/cpython/blob/v3.14.7/Lib/hashlib.py).

### Stream browser-extension payloads

[The CRX converter](../modules/home/helium-browser/scripts/crx-to-zip.py) now reads
only the fixed header, validates the payload offset against the opened file's
size, seeks past the variable header, and copies the ZIP payload in 1 MiB chunks.
CRX2 and CRX3 support and malformed-header errors remain covered by the packaged
helper check. Invalid input leaves an existing output intact. Output paths that
alias the input through the same path, a hardlink or a symlink are now rejected
before opening the output. The browser integration already supplies distinct
paths; in-place conversion is no longer supported by this internal helper.

Chromium defines CRX3 as a fixed prefix, a variable header and a ZIP payload.
`shutil.copyfileobj()` copies from the current stream position and bounds reads
when given a positive chunk length.
[Chromium format](https://github.com/chromium/chromium/blob/main/components/crx_file/crx3.proto),
[Python copying](https://docs.python.org/3.14/library/shutil.html#shutil.copyfileobj).

### Preserve laziness in native CI selection

[The native package selector](../.github/scripts/select-native-packages.sh) now
projects explicitly requested package names before evaluating their derivation
paths, for both current and historical revisions. This avoids forcing unrelated
packages in the representative Darwin build selection. Nix's lazy evaluation
permits this ordering.
[Nix language](https://nix.dev/manual/nix/2.35/language/).

An unknown current candidate still fails. A candidate absent from the historical
revision counts as new without forcing unchanged candidates to rebuild. Invalid
selected derivations still fail, and unavailable historical evaluation retains
the conservative fallback. Invocations without explicit candidates still inspect
the full package set. Hosted-build exclusions remain after evaluation to preserve
the existing evaluation-only policy. Candidate names use JSON serialization and
separate escaping of Nix interpolation; a regression case covers quotes,
backslashes and literal interpolation syntax.

### Measured results

Three trials per implementation used disposable local files on native x86 Linux,
Python 3.14.7, and the required workload runner. The baseline was captured before
these edits. These are `tracemalloc` peaks for Python allocations, not process RSS,
kernel page cache or total system memory. Files were reused without dropping the
page cache. Other desktop activity was not controlled, so elapsed-time samples
are illustrative rather than an end-to-end performance claim.

| Fixture | Previous median peak | Updated median peak | Reduction |
| --- | ---: | ---: | ---: |
| Source identity with one 16 MiB tracked file | 16.22 MiB | 0.38 MiB | 97.7% |
| Extract a 64 MiB CRX payload | 128.13 MiB | 2.26 MiB | 98.2% |

CRX elapsed-time medians were 86.9 ms before and 31.9 ms after. Ranges were
85.1 to 88.8 ms and 31.8 to 41.9 ms. Source-identity medians were 53.5 ms and 48.3 ms,
with overlapping ranges of 47.7 to 54.0 ms and 15.6 to 49.3 ms. Both identity runs
returned exactly the same fingerprint, including lockfile hashes, executable
mode, a symlink and a deleted tracked file. The new tests compare a captured
fingerprint and enforce generous allocation ceilings on large fixtures.

The source fixture contains 16 repetitions of `bytes(range(256)) * 4096` in
`large.bin`, executable mode, `link -> large.bin`, a tracked deleted file and
`flake.lock` containing `{}` plus a newline. The CRX fixture contains a version-3
header with four header bytes followed by 64 repetitions of that same block.
Measure each implementation in a fresh Python process, then repeat the operation
three times with `tracemalloc` restarted around each invocation. Keep fixtures and
raw results outside the repository.

The regression suite also verifies exact CRX payload digests across chunk
boundaries. Tests with an unrelated throwing Nix expression prove the CI selector
leaves that package unevaluated in both revisions. No hosted CI timing or desktop
responsiveness improvement is claimed. Wallpaper hashing uses the same streaming
API, but its memory change was not benchmarked separately.

## Follow-up implementation

A second pass found additional repeated work and failure-handling gaps.

The [wallpaper policy](../modules/home/desktop/scripts/wallpaper-policy.py) now
reads NUL-delimited filename input in 64 KiB chunks. It preserves filenames split
across reads, embedded newlines, non-UTF-8 filename bytes, and an unterminated final
record. Memory scales with the chunk and longest unfinished filename, rather than
the total candidate list. Python binary reads accept a maximum byte count and
preserve bytes without text decoding.
[Python binary I/O](https://docs.python.org/3.14/library/io.html#io.BufferedIOBase.read).

The same command builds its enabled-category index once and reuses it for each
candidate. It still reads provenance sidecars and applies the existing source and
category rules. The index lasts only for one invocation, so later preference
changes take effect on the next command. Declarative settings now validate before
a preference edit writes anything. Previously, a corrupt default could produce a
failed command after the override file had already changed.

[Spotify preference activation](../modules/home/scripts/configure-spotify-quality.sh)
now updates its six managed keys with one AWK pass per profile. It retains
unmanaged lines, deduplicates managed keys, and appends missing keys in the same
order. It compares the prepared result before replacement, preserving an unchanged
file's inode, timestamp and permissions. A changed file still uses a temporary
file in the same directory followed by rename. A function subshell confines the
cleanup trap; preparation, comparison and replacement failures propagate without
depending on the caller's `errexit` setting. Comparison status 1 means different
bytes, while status 2 is an error and must not permit replacement.
[GNU AWK arrays](https://www.gnu.org/software/gawk/manual/html_node/Arrays),
[GNU cmp statuses](https://www.gnu.org/s/diffutils/manual/html_node/Invoking-cmp.html).

The [CI selector](../.github/scripts/select-native-packages.sh) now compares only
historical names that remain in the current candidate map. Previously, an invalid
historical package that had since been removed could trigger the fallback and
rebuild every current package. Removed outputs cannot affect the build decision;
errors in retained historical candidates still trigger the conservative fallback.
Current-package validation and hosted-build exclusions remain intact. This follows
the same lazy-evaluation mechanism as the first-pass Darwin narrowing.
[Nix evaluation](https://nix.dev/manual/nix/2.35/language/evaluation.html).

## Deferred changes

SMART telemetry still follows the global 60-second interval. A longer per-input
interval would reduce privileged command launches and drive queries, but would
also delay health updates. The Prometheus output defaults to expiring metrics
after 60 seconds, so changing the collection interval alone can make metrics
disappear. A future change needs a freshness requirement and a matching expiry
policy. CPU and memory telemetry should retain their current cadence.
[Telegraf configuration](https://docs.influxdata.com/telegraf/v1/configuration/),
[Prometheus defaults](https://github.com/influxdata/telegraf/blob/master/plugins/outputs/prometheus_client/sample.conf).

Repeated nixpkgs imports in platform fixtures are another measurement candidate.
Sharing equivalent instances may reduce evaluation, but the fixtures intentionally
use different package policies and test multiple platforms. This review preserves
that coverage. It also retains extension-update freshness, security scanning,
network buffers, power profiles and retention policy because no measured result
justifies changing their behavior.

## Broad technique review

The following inventory separates upstream mechanisms from observed project
choices. Existing means present in the inspected source, not necessarily active.

| Technique | Evidence and current project decision |
| --- | --- |
| Bound parallel builds and per-build threads | Nix treats jobs and cores independently; their product can oversubscribe a host. Desktop source already sets two jobs and four cores in `hosts/nixos/desktop/local/system.nix`. Keep these until representative builds justify a change. [Nix guidance](https://nix.dev/manual/nix/2.32/advanced-topics/cores-vs-jobs). |
| Bound evaluator parallelism | Determinate supports parallel evaluation. Desktop already selects four evaluation cores after a recorded comparison. Shared automatic settings remain appropriate to other hosts until measured. [Determinate documentation](https://docs.determinate.systems/determinate-nix/parallel-eval/). |
| Avoid copying unused source trees | Determinate lazy trees copy demanded source content and are already enabled in `modules/shared/determinate.nix`. Do not disable them as a generic troubleshooting measure. [Lazy trees](https://docs.determinate.systems/determinate-nix/lazy-trees/). |
| Narrow derivation source files | `lib.fileset.toSource` controls the files entering a derivation. Documentation, Python, JavaScript, fonts and local-control checks already use filesets. Keep required fixtures; narrowing too far can make a check pass without the affected code. [Nixpkgs filesets](https://nixos.org/manual/nixpkgs/unstable/#sec-functions-library-fileset). |
| Avoid unrelated development inputs | `flake/partitions.nix` places checks, shells, formatter and apps in the dev partition. Upstream partitions support separate evaluation of these outputs. Retain the split. [flake-parts](https://flake.parts/options/flake-parts-partitions.html). |
| Reuse compatible package inputs | `flake.nix` already uses many `follows` edges. This avoids independently pinned dependency trees where compatibility permits. Do not force remaining upstream inputs to follow blindly; mismatched package variants can fail or lose cache compatibility. [Nix inputs](https://nix.dev/manual/nix/2.35/command-ref/new-cli/nix3-flake.html). |
| Prefer matching binary substitutes | Feature-aware caches and keys already live in `modules/shared/cache.nix`. Adding duplicate providers does not improve a missing exact derivation. The earlier CUDA scoping repair already preserves Sunshine's variant. [Nix settings](https://nix.dev/manual/nix/2.35/command-ref/conf-file.html). |
| Deduplicate store files | Shared `auto-optimise-store=true` hardlinks identical content. It adds work during store insertion; moving that work to a timer is a throughput/space tradeoff, not a proven gain here. [Nix settings](https://nix.dev/manual/nix/2.35/command-ref/conf-file.html#conf-auto-optimise-store). |
| Avoid competing garbage collectors | Determinate integration explicitly owns collection and earlier checks reject competing desktop GC schedules. Do not add `nh clean` or a second timer. Do not delete retained generations just to claim a speedup. [Existing integration](../modules/shared/determinate.nix). |
| Cache development environments | `modules/home/dev/direnv.nix` already enables nix-direnv and stores private cached layouts outside projects. Nix-direnv reuses environments and roots their dependencies against GC. Extra eager reevaluation or another daemon is unwarranted. [nix-direnv](https://github.com/nix-community/nix-direnv). |
| Use soft memory pressure plus hard containment | Desktop daemon and workload slices already combine MemoryHigh, MemoryMax and swap limits. Systemd recommends MemoryHigh as the primary control and MemoryMax as a last defense. Lowering limits can worsen reclaim or kill useful builds. [systemd 261.2](https://github.com/systemd/systemd/blob/v261.2/man/systemd.resource-control.xml). |
| Prioritize interactive I/O effectively | Existing `iocost.nix` enables an adaptive proportional controller, while the memory module sets weights. Kernel weights distribute relative sibling shares; a weight alone does not establish a controller. Retain the previous repair and measure real contention later. [Kernel cgroups](https://docs.kernel.org/admin-guide/cgroup-v2.html#io-interface-files). |
| Replace repeated polling with events | The queued workload waiter already polls `cgroup.events` for kernel notifications, and clipboard history uses Wayland watch mode. Kernel cgroup notifications cover descendant population changes. Reintroducing sleep loops would add wakeups and race windows. [Kernel notifications](https://docs.kernel.org/admin-guide/cgroup-v2.html#un-populated-notification). |
| Coalesce timer wakeups | Existing maintenance timers use AccuracySec. Systemd uses it to align expirations and reduce CPU wakeups. Preserve precise timeouts for interactive/security paths that require them. [systemd timer source](https://github.com/systemd/systemd/blob/v261.2/man/systemd.timer.xml). |
| Spread maintenance load | Scrub, scan, update, backup and wallpaper timers already use RandomizedDelaySec. Jitter spreads work; it does not guarantee two expensive jobs never overlap. A maintenance queue needs a measured contention case before adding more coordination. [systemd timer source](https://github.com/systemd/systemd/blob/v261.2/man/systemd.timer.xml). |
| Compress swap in RAM | Reusable zram uses one zstd device with higher swap priority. The host has a bounded logical capacity; the module rejects simultaneous zswap. Capacity is not RAM preallocation. Keep the configuration and measure physical compression and pressure. [Kernel zram](https://docs.kernel.org/admin-guide/blockdev/zram.html). |
| Use cheap filesystem compression | Btrfs mounts already select zstd level 1 and noatime. Normal compression skips data judged incompressible. Higher levels and forced compression can spend CPU on game assets and archives without useful savings. [Btrfs compression](https://btrfs.readthedocs.io/en/latest/Compression.html). |
| Batch SSD discard | Root storage already chooses nodiscard plus weekly TRIM, with monthly scrub and a bandwidth bound. Async discard is also supported; replacing a deliberate periodic policy needs I/O measurements. [Btrfs discard](https://btrfs.readthedocs.io/en/latest/Trim.html). |
| Choose tmpfs by workload | Desktop temporary storage uses tmpfs. It competes for memory and can swap. Disk-backed build scratch may help only if temporary files cause measured pressure; changing all temporary storage trades memory for device I/O. [Kernel tmpfs](https://docs.kernel.org/filesystems/tmpfs.html). |
| Reduce security scanner overhead without weakening coverage | ClamAV already uses a resident daemon, four workers, bounded queue, narrow on-access ingress paths and weekly broader scans. Disablement would change the intended protection. Upstream clamdscan reuses the daemon database. [ClamAV scanning](https://docs.clamav.net/manual/Usage/Scanning.html). |
| Bound logs and subprocess output | Evidence commands already write their logs to files, and the Git privacy hook already streams cat-file bodies. Python warns that communicate buffers captured output in memory. Preserve redacted error handling and bounded pipes; small JSON captures do not warrant blanket rewrites. [Python subprocess](https://docs.python.org/3.14/library/subprocess.html#subprocess.Popen.communicate). |
| Avoid obsolete CI runs | `.github/workflows/ci.yml` already cancels superseded PR runs while preserving merge-queue work and skipping draft-heavy jobs. Native package selection compares derivation paths. Broader path filters can suppress required checks or miss transitive changes. [GitHub concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency). |
| Reduce Git indexing work | Git already enables feature.manyFiles, commit-graph writes, index threads and Darwin fsmonitor. Preserve platform-specific support and repository semantics instead of removing status information for speed. [Git configuration](https://git-scm.com/docs/git-config). |
| Measure the cost of metrics | Telegraf already samples at 60 seconds; desktop UI rates range from 5 to 30 seconds. Per-input intervals are available, but slower rates sacrifice freshness. Profile collectors before changing responsive UI metrics. [Telegraf configuration](https://docs.influxdata.com/telegraf/v1/configuration/). |
| Measure pressure and power, not only usage | PSI measures stalled time. The evidence recorder captures repeated trials; the earlier desktop review measured PSI separately. A power-profile change needs task time, energy and responsiveness observations; no source establishes one universal optimum. [PSI](https://docs.kernel.org/accounting/psi.html), [AMD P-state](https://docs.kernel.org/admin-guide/pm/amd-pstate.html). |

## First-pass validation and limits

Validation ran on native x86 Linux through `workstation-task`.

- The native CI selection suite passed 29 tests and six subtests using real Git
  history and Nix evaluation.
- The focused Python run passed 167 cases, including the new memory and alias
  checks and the wallpaper suites. Six evidence-schema cases failed because
  concurrent schema changes and their existing fixtures were inconsistent.
  Those same six failures reproduced in a private source copy with the hashing
  optimization removed. They concern receipt comparison and manifest validation;
  this is not a claim of an entirely passing Python suite.
- `checks.x86_64-linux.non-bash-python-helpers` built and passed, exercising the
  packaged CRX command with valid CRX2/CRX3 and nine malformed inputs.
- Ruff passed the converter, wallpaper helper and changed tests. ShellCheck and
  shfmt passed the selector; Ruff formatting passed all six Python files. Four
  Ruff findings remain in concurrently edited evidence receipt/measurement
  functions, outside the source-hashing change.
- The changed-file type check reported one `subprocess.run` overload error in
  the concurrently edited evidence runner, outside the hashing hunk. It reported
  no diagnostics in the other five Python files.
- The report passed rumdl, relative-link validation and the repository Gitleaks
  rules against a private copy of the task files. Independent code review found
  no actionable issues; research review corrected the opening summary and the
  distinction between trial recording and separate PSI observations.

No NixOS activation, system deployment, native Darwin execution, live extension
update or hosted CI run was performed. These source/helper changes do not require
changing the running desktop. Existing host optimizations in the inventory above
were inspected but are not attributed to this implementation.

## Follow-up validation

The pinned native Linux run passed 243 tests across wallpaper, Spotify and
evidence helpers. One evidence case requiring the Nix daemon was deselected by the
repository's declared execution markers. Native CI selection passed 30 tests and six subtests using real Git and
Nix. The changed-file type check passed, including the evidence runner and its
tests. The first-pass schema failures have been repaired by concurrent work and
no longer reproduce in this current suite; that repair is separate from these
optimizations.

Against the saved pre-change implementations, nine regression cases failed as
expected. They cover oversized filter allocations, mutation after invalid
configuration, repeated preference passes, unnecessary file replacement and
failure cleanup. The updated implementation passes those same cases. Independent
review found no actionable correctness or standards findings. Ruff, ShellCheck,
shfmt, Nix parsing and Nix formatting passed for the affected files.

The 50,000-filename filter fixture reduced median peak Python allocation from
20.87 MiB to 0.32 MiB across three trials, about 98.5%. Each record was a retired
provider filename followed by NUL; one accepted filename ended the stream without
a delimiter. Both versions emitted identical bytes. As in the first pass, these
are `tracemalloc` allocations, excluding page cache and process RSS.

This fixture did not show a CPU-time improvement. Instrumented elapsed medians
were 334.9 ms before and 378.2 ms after, with overlapping ranges of 330.9 to
395.0 ms and 365.1 to 416.4 ms. The result supports bounded memory, not a claim of
higher filter throughput. It does not measure category-index reuse because the
retired candidates exit before category planning.

The Spotify fixture observed two AWK launches for two profiles, compared with
twelve before, and retained exact inode, modification time and mode on a no-op.
The historical CI regression also failed against the saved selector and passed
after the fix, confirming that an invalid retired output no longer rebuilds an
unchanged current package.

A standalone Nix build rendered the actual Spotify module's activation script
with the pinned Linux package set and passed ShellCheck on that generated file.
The first version of this check discarded Nix string context while extracting the
script path and therefore failed to build its dependency. Preserving that context
repaired the check; no production change was needed. This verifies generation and
build, not a live Spotify or Home Manager activation. Native Darwin execution
remains untested.
