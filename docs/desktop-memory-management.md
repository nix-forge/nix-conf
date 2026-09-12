# Desktop memory management

Run memory-intensive development commands as the desktop user through the
explicit workload runner:

```sh
workstation-task nix build --max-jobs 1 --cores 2 .#<TARGET>
workstation-task nix flake check --no-build
workstation-task nix develop --command <COMMAND>
```

Standard `nix` remains unchanged. Heavy local build and check recipes in the
root justfile use the runner. Direct commands, spawned agents, other repositories,
and other checkouts must use it explicitly. Install the desktop home profile to
make the runner available; it refuses work if its matching resource policy is
missing.

## Queue and failure behavior

Every invocation for the desktop user shares one lock in
`$XDG_RUNTIME_DIR/workstation-background.lock`. The runner preserves arguments,
environment, working directory, stdin, stdout, stderr, and the foreground
command's exit status. Independent callers queue. Nested calls reuse their
existing workload scope after checking the policy.

Each command and its ordinary child processes enter a separate systemd scope
under `background-workload.slice`. The queue stays held until all descendants
exit, including children left in the background. Use ordinary user services for
persistent daemons instead of starting them in this queue. Cancellation with
INT, TERM, or HUP stops only the invocation's scope before releasing its lock.
After the foreground command exits, the runner blocks on the scope's
`cgroup.events` notifications until its descendants finish. It does not repeatedly
query systemd. See the [kernel's populated notification contract](https://docs.kernel.org/admin-guide/cgroup-v2.html#un-populated-notification).
SIGKILL cannot run cleanup; aggregate cgroup limits still apply to surviving
work, which must be inspected before starting another heavy task.

The queue is per user on one host. It does not serialize root jobs or remote
builders. Run remote development commands through the desktop user's runner on
the desktop. A local `workstation-task deploy ...` does not wrap a remote Nix
client. The daemon's separate budget still applies to its builders. Programs
that explicitly start services or new scopes can leave the runner's group;
this policy controls cooperative development work, not hostile code.

## Resource policy

The [host memory module](../hosts/nixos/desktop/local/memory.nix) owns the budgets.
It protects session and interactive application memory through the required
ancestors. These are best-effort reclaim protections, not reserved physical RAM
or immunity from the kernel OOM killer. Compressed swap and the kernel also need
physical memory.

Background jobs share an aggregate slowdown threshold, hard memory ceiling, and
swap ceiling. They have lower CPU and I/O weights. `systemd-oomd` monitors only
the background workload subtree and can terminate an entire task under sustained
pressure. A confined kernel OOM likewise terminates that task as a group.
Interactive application scopes retain their child-OOM survival policy.

Inspect the actual settings and pressure with:

```sh
oomctl dump
systemctl --user show background-workload.slice session.slice app.slice
cat /proc/pressure/memory
free -h
swapon --show
```

Zram keeps a bounded logical capacity without a smaller resident cap. A resident
cap can fail swap writes before the logical device fills; it is not a reliable
spill threshold for disk swap. See the [kernel zram documentation](https://docs.kernel.org/admin-guide/blockdev/zram.html)
and [resource-control documentation](https://github.com/systemd/systemd/blob/v261.2/man/systemd.resource-control.xml).

## Persistence and recovery

Runtime settings are separate from NixOS and Home Manager activation. During
recovery, retain existing applications and temporary recovery swap. Stage a
reviewed system for the next boot instead of switching an active plaintext swap
device to encryption. The pre-switch check rejects live conversion before NixOS
can call `swapoff`; the setup service separately checks the partition before
opening its encrypted mapping. Administrators can bypass pre-switch checks, so
keep that check enabled during this transition.

Random swap encryption protects future writes. It does not erase historical
plaintext swap pages, encrypt temporary recovery swap, or encrypt the root
filesystem. Older generations that refer to the old swap label lose their disk
swap after conversion. Preserve a tested recovery path for the eventual reboot.
No hibernation is supported with fresh random swap keys.

On unencrypted root, automatic core processing and storage are disabled because
dumps can contain credentials. After root encryption, small bounded dumps are
permitted. Home Manager preserves regular-file conflicts in private unique
backup directories; an activation step also handles the foreign Hyprland symlink
that its normal backup hook does not handle. Dry runs preserve the original files.

## Validation

Build the generated policy without building unrelated desktop applications:

```sh
workstation-task nix build --no-link --print-out-paths \
  .#nixosConfigurations.desktop.config.system.build.desktopMemoryPolicy
```

Run the native integration probe outside the workload runner so it can test
independent queue callers. It requires `strace` to detect repeated status probes
and cgroup waits that spin instead of blocking:

```sh
bash tests/systemd/check_workstation_task.sh <POLICY_STORE_PATH>
python3 tests/systemd/check_chatgpt_oom.py
```

The OOM probes allocate only within disposable 96 MiB groups. They do not test
whole-machine exhaustion or prove that applications recover after losing an
essential child process.
