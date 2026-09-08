# ChatGPT exits after a task runs out of memory

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
