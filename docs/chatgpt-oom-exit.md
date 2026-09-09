# ChatGPT exits after a task runs out of memory

## Current configuration on 2026-09-08

Both ChatGPT scope families now use `OOMPolicy=continue` through
[the desktop integration](../homes/desktop/local/interactive-desktop.nix).
The [host configuration](../hosts/nixos/desktop/local/system.nix) sets
`max-jobs=2`, `cores=4`, and the following daemon limits:

| Setting | Value |
| --- | --- |
| Memory pressure threshold | 6 GiB |
| Memory ceiling | 8 GiB |
| Swap ceiling | 1 GiB |
| CPU weight | 50 |

The daemon properties were applied with `systemctl set-property --runtime`
and verified without restarting the daemon. That override lasts until reboot;
normal NixOS reactivation is needed to persist the declared daemon policy.
The ChatGPT scope overrides are already installed. The
[scope regression](../tests/systemd/check_chatgpt_oom.py) passed for both
prefixes after the missing Hyprland policy was added.

The experimental `nix-workload` runner has been removed from the user package
profile and repository, together with its shared-slice declaration and tests.
Its earlier Nix command replacements, forwarding profile entry, and shell PATH
addition were also removed. Auditing `$HOME/.local/bin` found only the four
experimental workload links; removing them left the directory empty.
No replacement package was built or installed as part of this removal.
Reactivation remains a separate step.

User-side Nix evaluations now have no memory budget supplied by this feature.
The daemon ceiling applies to its builders, and the ChatGPT policy prevents
systemd from stopping surviving scope members after a child OOM. Neither
setting guarantees survival if the kernel directly kills an application process.
The incident analysis below explains that distinction and the remaining risk
from overlapping large evaluations.

## Review on 2026-09-08

The latest exit followed another global out-of-memory event. The previous
Chromium scope policy remains effective, but does not cover every ChatGPT
process. Preventing recurrence requires workload memory limits as well as
completing that policy coverage.

### Observed failure

The kernel reported only 52 KiB of free swap out of 23.2 GiB. Three user-owned
Nix processes held approximately 5.31, 5.25, and 2.22 GiB of resident memory,
or 12.8 GiB combined. They were the three largest resident processes in the
OOM listing. This establishes concurrent Nix memory pressure; the listing
alone does not identify their exact commands or prove a memory leak.

At 11:55:47 PDT, the kernel killed a ChatGPT process with about 871 MiB of
resident anonymous memory and `oom_score_adj=300`. It belonged to
`app-Hyprland-chatgpt-<instance>.scope`, which the user manager marked
`oom-kill`. At 11:55:48, the main ChatGPT process trapped with `SIGTRAP`.
Its last application log reported a GPU child process launch failure.
The coredump collector was itself killed during another global OOM at
11:56:51, leaving no completed systemd coredump.

These observations establish memory exhaustion followed by an application
crash. They do not establish the native code path that triggered `SIGTRAP`.
Failure to recover GPU processes after a scope shutdown is a possible link,
but the missing dump prevents confirmation.

The running replacement has processes in both scope families:

| Scope prefix | Effective policy | Existing override |
| --- | --- | --- |
| `app-org.chromium.Chromium-` | `OOMPolicy=continue` | Present |
| `app-Hyprland-chatgpt-` | `OOMPolicy=stop` | Absent |

The surviving old Chromium scope reached about 17.2 GiB of memory, while
the failed Hyprland scope reported a 3 GiB peak. Cgroup membership, rather
than the application's visible name, determines which policy applies.
systemd documents that `stop` terminates the remaining processes, whereas
`continue` leaves them running after the OOM event.
[Service policy](https://github.com/systemd/systemd/blob/v261.2/man/systemd.service.xml#L1182),
[scope support](https://github.com/systemd/systemd/blob/v261.2/man/systemd.scope.xml#L97).

### Controlled verification

The existing [OOM regression workload](../tests/systemd/check_chatgpt_oom.py)
was run inside a disposable scope using the missing Hyprland prefix:

```sh
systemd-run --user --scope --quiet \
  --unit=app-Hyprland-chatgpt-oom-review-before.scope \
  --property=MemoryMax=96M --property=MemorySwapMax=0 \
  python3 tests/systemd/check_chatgpt_oom.py --workload
```

The allocator exceeded the confined limit, and the healthy parent also
terminated with exit status 143. The scope reported `Result=oom-kill` and
`OOMPolicy=stop`.

Repeating with a fresh scope name and `--property=OOMPolicy=continue` produced:

```text
PASS: child OOM recorded; application parent survived
```

The original `python3 tests/systemd/check_chatgpt_oom.py` also passed,
confirming that the Chromium policy still works. The test scopes were cleaned
up. These tests exercise systemd's collateral termination behavior within
96 MiB, without deliberately exhausting host memory. They do not reproduce
ChatGPT's native `SIGTRAP` or prove that it recovers after losing a renderer
or GPU process.

### Recommended changes

1. Extend the existing Home Manager policy in
   [the desktop integration](../homes/desktop/local/interactive-desktop.nix)
   to `systemd/user/app-Hyprland-chatgpt-.scope.d/50-oom-policy.conf` with
   `[Scope]` and `OOMPolicy=continue`. Keep the Chromium override. This is
   the narrowly tested correction for the uncovered process group.
2. Launch memory-heavy Nix client tasks in separate systemd scopes with a
   shared memory budget. Use `MemoryHigh` for pressure control and
   `MemoryMax` as a hard ceiling. Set a bounded swap budget as well. A shared
   slice or serialized admission is necessary: separate per-command limits
   still allow several commands to exhaust the machine together. Verify
   actual cgroup placement and account for tasks started outside the wrapper.
3. Apply the pending desktop `max-jobs=2` and `cores=4` settings from
   [the host configuration](../hosts/nixos/desktop/local/system.nix).
   At review time, the installed configuration still used `max-jobs=auto`
   and the effective default `cores=0`. These settings govern builds and
   do not bound the memory of independently running Nix clients.
4. Budget the Nix daemon's builders separately. The daemon and user-side
   evaluators occupy different cgroups, so a daemon-only cap would not
   contain the large user-owned processes observed in this event. Choose
   the two budgets together, leaving room for desktop applications, the
   kernel, and compressed swap.

These recommendations follow systemd's guidance to use `MemoryHigh` as
the main control and `MemoryMax` as the last defense. The kernel documents
that cgroup limits apply hierarchically and that an OOM caused by
`memory.max` stays inside the constrained cgroup. Start each task inside
its scope: moving a process later does not migrate existing memory charges.
[systemd resource controls](https://github.com/systemd/systemd/blob/v261.2/man/systemd.resource-control.xml#L325),
[kernel cgroup v2 documentation](https://docs.kernel.org/admin-guide/cgroup-v2.html).

The launch structure, after configuring the shared slice and choosing
budgets, is:

```text
systemd-run --user --scope --slice=<WORKLOAD-SLICE> \
  -p MemoryHigh=<HIGH> -p MemoryMax=<MAX> -p MemorySwapMax=<SWAP> \
  <COMMAND>
```

Scope mode preserves the caller's environment and waits for the command.
[systemd-run documentation](https://github.com/systemd/systemd/blob/v258/man/systemd-run.xml#L57).
Nix's official build-machine guide also recommends limiting daemon memory.
Its example dedicates most memory to builds; an interactive desktop needs
a smaller budget coordinated with client workloads.
[Nix build-machine setup](https://nix.dev/tutorials/nixos/distributed-builds-setup.html).

Setting `OOMPolicy=continue` cannot stop the kernel from choosing a ChatGPT
process as its direct victim. It also cannot guarantee that ChatGPT survives
losing that process. Workload isolation and aggregate memory limits address
the exhaustion that triggered this incident. The expected tradeoff is that
an oversized task can fail while the desktop retains memory.

The running `systemd-oomd` had no monitored cgroups. Enabling its service
alone therefore did not provide proactive workload eviction. If introduced,
monitor a dedicated workload hierarchy; the broad application hierarchy
currently contains ChatGPT and its tasks together.
[systemd-oomd documentation](https://github.com/systemd/systemd/blob/v261.2/man/systemd-oomd.service.xml).

### Evaluation concurrency and updates

The effective live settings were `max-jobs=16`, `cores=0`, and `eval-cores=0`.
`max-jobs` governs local builds, and `cores` supplies the builder's
`NIX_BUILD_CORES` value.
[Nix configuration reference](https://nix.dev/manual/nix/2.34/command-ref/conf-file.html#conf-max-jobs).
Determinate's separate `eval-cores=0` permits all available CPU cores for
parallel evaluation. Comparing `eval-cores=1` inside a constrained scope
is reasonable, but any memory improvement must be measured. Serializing
separate expensive evaluations directly avoids overlapping their peaks.
[Determinate evaluation settings](https://manual.determinate.systems/command-ref/conf-file.html#conf-eval-cores).

Determinate Nix 3.22.3 includes evaluation-cache repairs, parallel evaluation
improvements, and clearer allocation-failure messages. The OOM reporting
change still terminates on allocation failure and cannot intercept kernel
`SIGKILL`. It is not evidence of a fix for this ChatGPT exit.
[Release notes](https://manual.determinate.systems/release-notes-determinate/v3.22.3.html),
[allocation-failure change](https://github.com/DeterminateSystems/nix-src/pull/603).

### Scope of this review

Validation ran on Linux with systemd 261.2 and Determinate Nix 3.22.2,
reporting Nix 2.35.2. This review updated documentation only. No application
restart, configuration change, package update, system build, or activation
was performed. Memory thresholds and application recovery still require
validation before claiming prevention of the complete crash sequence.

## Earlier incident and mitigation on 2026-09-07

On 2026-09-07, ChatGPT Linux 26.901.41600 exited on `desktop` at 12:25 and
15:02 PDT. Both exits coincided with the kernel killing a Nix process inside
the app's Chromium scope. No systemd coredump was recorded.

At 15:02:07, the kernel reported a global OOM with only 68 KiB of swap free
out of 24,355,320 KiB. It killed Nix PID 3467105, which held about 6.7 GiB of
resident anonymous memory. Its cgroup was
`app-org.chromium.Chromium-2919949.scope`. The app's log filenames identify
2919949 as that ChatGPT instance's main PID.

The user manager then marked that scope `oom-kill`. Its recorded peak usage
was 14.6 GiB of memory and 7.3 GiB of swap. ChatGPT's outer UWSM scope exited
at the same time. The earlier incident followed the same sequence with
ChatGPT PID 1214367 and Nix PID 2905628.

The replacement ChatGPT process and its tasks also share a Chromium scope.
Its original `OOMPolicy` was `stop`, inherited from the user manager.
[systemd's OOM policy documentation](https://github.com/systemd/systemd/blob/main/man/systemd.service.xml)
explains that this policy stops the unit's remaining processes when the
kernel kills one member. This accounts for the GUI disappearing when a task
runs out of memory. It does not require a fault in ChatGPT's renderer.

The desktop Home Manager configuration now installs
`systemd/user/app-org.chromium.Chromium-.scope.d/50-oom-policy.conf` with
`OOMPolicy=continue`. A matching file was installed in the current user's
configuration and the user manager reloaded. The running ChatGPT scope
reported `ActiveState=active` and `OOMPolicy=continue`, without restarting
the app. This prefix also covers ordinary Chromium scopes, which receive
the same behavior. Other application scopes retain their previous policy.

The desktop NixOS configuration now limits Nix to two concurrent builds,
with four cores per build. Previously, `max-jobs=auto` and `cores=0` allowed
16 concurrent builds, each requesting all 16 CPUs on this 30 GiB machine.
Multiple compilers were present in the OOM process listing, and the daemon
had a recorded memory peak of about 14.5 GiB. Lower concurrency should reduce
pressure, but it is not a memory limit and does not bound client evaluations.
These system-wide build settings were evaluated successfully but await the
next NixOS activation. The live OOM policy fix is already effective and
persists across application restarts and reboot.

Validation used `python3 tests/systemd/check_chatgpt_oom.py`. This creates a
temporary scope with the same Chromium name prefix and caps it at 96 MiB
with no swap. A child allocates 128 MiB and makes itself the preferred OOM
victim. The test checks that the kernel recorded an OOM kill and that the
healthy parent survives long enough for systemd to process the event.

Before the policy change, the result was:

```text
FAIL: child OOM also terminated the application parent
```

After the policy change, the result was:

```text
PASS: child OOM recorded; application parent survived
```

Nix evaluation confirmed the Home Manager drop-in text and the desktop's
`max-jobs=2` and `cores=4`. Formatting checks passed for both modified Nix
files. No full system build or activation was performed because the checkout
contains substantial unrelated pending work. The reproduction exercises
systemd's failure handling without exhausting the workstation's memory.
The kernel can still kill ChatGPT itself if it becomes an OOM victim; this
fix prevents systemd from additionally terminating it after a child is killed.
