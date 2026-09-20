# ClamAV scan memory research

Reviewed: 2026-09-14. Scope: the repository's ClamAV module and its scheduled
scanner. Decision: reduce memory pressure during scheduled scans without
removing the daemon, on-access protection, signature updates, or scheduled
coverage.

## Answer

Make the smallest low-risk change in the host-local `clamd` settings:

```nix
ConcurrentDatabaseReload = false;
```

ClamAV documents that concurrent reload keeps a second scanning engine in memory
while the old engine continues to serve scans. It is enabled by default and uses
more RAM. The configured update timer can overlap the long-running weekly scan,
so turning it off prevents that known whole-database duplication. During a
database reload, scans wait briefly instead of competing with two engines. All
existing scan roots, on-access watch paths, signature updates, and detection
settings remain unchanged.

This change is now applied in
[`hosts/nixos/desktop/local/security-clamav.nix`](../hosts/nixos/desktop/local/security-clamav.nix).
It is not a hard memory ceiling. The evidence does not support a safe numeric
`MemoryHigh` or `MemoryMax` value yet. A cap on `clamdscan.service` alone would
also be misplaced because the daemon, not its client, owns the scan work. If the
change does not reduce the measured peak enough, measure the memory charge of
the complete `system-clamav.slice` through one representative scan, then add a
slice-level `MemoryHigh` with a tested `MemoryMax` as the last defence.

## Findings and sources

### Repository observations

The supplied, redacted observations report a resident daemon of about 0.8 GiB,
several GiB of swap use, and a historical peak near 9 GiB. The weekly scan ran
for more than five hours, read about 3.8 GiB, reached about 4 GiB, and ended
with four inaccessible-file errors.

The configured scan covers each normal user's complete home plus `/etc`, `/tmp`,
`/var/lib`, and `/var/tmp`. It calls `clamdscan --multiscan --fdpass` through a
regular-file enumerator, with `MaxThreads = 4` and `MaxQueue = 8`.
The host-local policy defines those roots and settings. [The shared
module](../modules/nixos/security/clamav.nix) installs the wrapper, and [the
wrapper](../modules/nixos/security/clamav-scan.sh) uses the stated client
options. The four errors are expected to remain failures:
the focused test deliberately preserves unreadable inputs as nonzero results.

On-access prevention is intentionally limited to each normal user's Downloads
and Desktop directories. That is a narrow ingress policy, not a whole-home
watch.

### Documented behavior

The evaluated configuration uses ClamAV 1.5.4 from the pinned nixpkgs revision
`c5c4a43b0e8056328ec4529f735cabdb8f1942bb`. Sources were retrieved on
2026-09-14.

- `clamdscan` sends work to an already-running `clamd`. With a local socket,
  `--fdpass` opens the file in the client and gives its descriptor to the daemon.
  Combined with `--multiscan`, it submits individual file scans that the daemon
  can process in parallel. `--allmatch` has no effect in this mode. [ClamAV
  scanning guide](https://docs.clamav.net/manual/Usage/Scanning.html) and
  [ClamAV 1.5.4 `clamdscan` manual](https://github.com/Cisco-Talos/clamav/blob/clamav-1.5.4/docs/man/clamdscan.1.in).
- `MaxThreads` is the maximum number of simultaneous daemon threads. `MaxQueue`
  includes work being processed; the ClamAV sample recommends at least twice as
  many queue entries as threads and warns against increasing the queue without
  considering file-descriptor use. The current queue meets that relationship.
  [ClamAV 1.5.4 sample configuration](https://github.com/Cisco-Talos/clamav/blob/clamav-1.5.4/etc/clamd.conf.sample).
- The same sample says that `ConcurrentDatabaseReload` temporarily loads a
  second engine, uses more RAM, defaults to enabled, and may instead block scans
  during reload for lower RAM use. [ClamAV 1.5.4 sample
  configuration](https://github.com/Cisco-Talos/clamav/blob/clamav-1.5.4/etc/clamd.conf.sample).
- ClamAV's `MaxScanSize`, `MaxFileSize`, `MaxRecursion`, and `MaxFiles` limit
  work per input container. The sample warns that disabling or raising several
  of these limits can severely harm the system. The configuration does not
  override them, so the package defaults apply. [ClamAV 1.5.4 sample
  configuration](https://github.com/Cisco-Talos/clamav/blob/clamav-1.5.4/etc/clamd.conf.sample).
- ClamAV describes on-access scanning as a separate client that asks `clamd` for
  verdicts. Prevention mode can seriously hurt performance on commonly accessed
  directories, which supports keeping the watch list narrow. [ClamAV scanning
  guide](https://docs.clamav.net/manual/Usage/Scanning.html).
- NixOS places its daemon, updater, and scanner services in
  `system-clamav.slice`; its scanner defaults also name the mutable system
  directories used here. [NixOS ClamAV module at the pinned release
  branch](https://github.com/NixOS/nixpkgs/blob/nixos-25.05/nixos/modules/services/security/clamav.nix).
- systemd describes `MemoryHigh` as its main memory-throttling mechanism and
  `MemoryMax` as an absolute limit that can invoke the unit-local OOM killer.
  [systemd 261.2 resource-control manual](https://github.com/systemd/systemd/blob/v261.2/man/systemd.resource-control.xml).

### Inference

The supplied peak data does not prove a cause. It is consistent with two
independent contributors: up to four active daemon scan workers and a database
reload that temporarily retains two engines. The duration makes an update/scan
overlap plausible because updates are scheduled every four hours, but no event
timestamps were retained to prove that overlap.

`ConcurrentDatabaseReload = false` addresses the documented duplicate-engine
case without reducing coverage. It does not bound memory used by one pathological
input or by four simultaneous scan workers. Lowering `MaxThreads` would reduce
that concurrency, but it can delay on-access verdicts while the weekly job runs,
so it is not the first safe change without a measured latency requirement.

## Validation and limits

This research read the evaluated configuration and the installed ClamAV 1.5.4
sample and manual. It also checked the NixOS module at the pinned release branch
and systemd 261.2 documentation. The repository change was applied, but no
system build or activation ran, and no raw logs or account-specific paths were
retained.

The existing focused tests show that the wrapper skips special files, preserves
unreadable-file failures, and can access the intended temporary directories.
They do not measure ClamAV memory, reload overlap, scan duration, or on-access
latency. Verify the recommendation with one scheduled-equivalent scan, recording
only redacted slice-level peak memory, swap, result, duration, and inaccessible
path count.

## Implication for this repository

`ConcurrentDatabaseReload = false` is now under the existing daemon settings in
the host-local ClamAV policy. Run the existing focused ClamAV checks and one
controlled runtime measurement after evaluation. Do not add a numerical
systemd memory limit until that measurement establishes a value above ordinary
daemon and scan demand but below the level that harms interactive work.
