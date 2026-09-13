# Record workstation validation

Validation records identify the tracked source, dirty edits, initialized
submodules, lockfiles, platform, check and execution phase. Store the records and
raw command logs outside the repository. They can contain operational details.
The command uses a private directory under `$HOME/.local/state/nix-conf/evidence`
by default. A failed verification keeps bounded private diagnostic output in the
file named by its receipt's `verification_log`, including failures before the
measured command starts. Review and redact evidence before sharing it.

## Capture a build

On the desktop host:

```sh
just desktop-validation-build
```

This runs the existing `just os-build desktop` recipe through the workload queue.
The evidence command evaluates the candidate system output, checks that the
successful build realized it, and records its store path. It does not activate
the result. Source changes during the command invalidate the receipt.

On the native Apple Silicon Mac, run the equivalent build with its target:

```sh
just evidence run --target macbook-pro-m4 --check full-system --phase build \
  --installable darwinConfigurations.macbook-pro-m4.system \
  -- just darwin-build macbook-pro-m4
```

Evaluation, builds, dry activation, actual activation, VM tests, hardware checks
and recovery establish different things. A check on the wrong platform cannot
substitute for a required native result. Untracked files are outside a Git flake
source. Add intended new source files with `git add -N` before validation.

## Check a running generation

After a separately authorized activation, pass the matching build receipt to
runtime checks. The command compares the candidate output with the active system
before and after execution. This example verifies the user portal service:

```sh
just evidence run --target desktop --check portals --phase runtime \
  --build-receipt <BUILD_RECEIPT_JSON> \
  -- systemctl --user is-active xdg-desktop-portal.service
```

That result establishes service activity only. The screen-sharing acceptance
check must separately exercise an application capture and confirm that frames
reach the requesting application. Login, lock/unlock, audio output and input,
suspend/resume, display reconnection and rollback also require their actual
user-visible operations. Never record `true` or another placeholder as a pass.

Inspect the release inventory and compare receipts with its requirements:

```sh
just validation-manifest > <PRIVATE_MANIFEST_JSON>
just evidence status <PRIVATE_MANIFEST_JSON> <RECEIPT_JSON>...
```

Missing, invalid, skipped or failed required evidence keeps the result incomplete.
A later failure supersedes an earlier pass for the same source and check.
Record an omitted check explicitly when its required hardware is unavailable:

```sh
just evidence skip --target starter --check home --phase build \
  --system aarch64-linux --reason "Native ARM Linux builder unavailable"
```

`status` also accepts a manifest without receipts and reports every requirement
as missing. Activation and dry activation require `--build-receipt`; records
check the active system before and after the command.
A clean revision number alone is insufficient for a dirty working tree.

## Measure performance

Measure one phase at a time. Do not mix evaluation, cache downloads, local builds
and activation into a number called build performance. Use repeated trials with
an explicitly described cache condition:

```sh
just evidence benchmark --target desktop --check evaluation --phase evaluation \
  --cache-condition warm --runs 3 \
  -- nix eval --raw .#nixosConfigurations.desktop.config.system.build.toplevel.drvPath
```

Run the same command against each candidate source with the same hardware,
workload and cache conditions. Comparison also requires matching effective Nix
client configuration and machine, executable and environment fingerprints. Failed
configuration capture makes a performance comparison unavailable; it does not
mean two unknown configurations match. This does not measure daemon or remote
builder configuration. For changes in the evaluator's own cache behavior,
record that behavior explicitly rather than calling every repeated invocation a
warm-cache comparison. The command does not clear caches or delete store paths.

```sh
just evidence compare <BASELINE_JSON> <CANDIDATE_JSON> --budget-percent 10
```

The budget is a proposed acceptance threshold, not a measured speedup. Compare
medians and ranges; overlapping ranges indicate that a small change may be
ordinary variation. Choose the budget after collecting a representative baseline.

Peak RSS is the OS maximum for the measured command and its waited children.
It is not simultaneous process-tree memory and excludes Nix daemon and remote
builder resources. Use the existing desktop pressure and cgroup tooling when
measuring those resources. For responsiveness, record a repeatable foreground
operation during the same background workload and compare its latency tails
alongside background completion time. A fast evaluation does not prove a smooth
desktop or game session.

## Publish reviewed evidence

Use a release evidence table with a source identity, platform, phase, result,
date and remaining checks. Link reviewed summaries to the relevant guide and
keep raw logs private. A record is local evidence supplied by its operator,
not a signed third-party attestation. The command validates its structure and
provenance relationships; it cannot establish that a human observation is honest.

Use the [reader pilot](reader-pilot.md) to test the public guide independently of
the maintainer's machines. External reader results remain pending until actual
readers complete the steps.
