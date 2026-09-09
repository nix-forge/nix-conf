# Quiet Crashpad report-lock contention

The Linux Determinate Nix CLI uses Sentry Native's Crashpad backend. Concurrent
CLI processes can inspect the same completed crash report. Crashpad's generic
database creates a per-report lock with exclusive creation. An existing lock
means the report is busy, but the logging open helper emits an error before the
database returns that status. This does not indicate a failed Nix build.

## Upstream investigation

Reviewed on 2026-09-09 against Determinate Nix 3.22.3, Sentry Native 0.13.5,
and its Crashpad revision `e5040b878718f5c004d0ecfe1747642c72ddcd39`.
GitHub issue and PR searches covered DeterminateSystems/nix,
DeterminateSystems/nix-src, DeterminateSystems/determinate,
getsentry/sentry-native, and getsentry/crashpad. No matching fix or fixed release
was established.

- [Determinate Nix PR #418](https://github.com/DeterminateSystems/nix-src/pull/418)
  introduced Sentry integration.
- [Crashpad PR #162](https://github.com/getsentry/crashpad/pull/162) serializes
  pending-report processing within one uploader. Its thread mutex does not fix
  contention between separate processes accessing a shared database.
- [Determinate Nix issue #626](https://github.com/DeterminateSystems/nix-src/issues/626)
  concerns cache placement when the home directory is unavailable, a different bug.
- The [pinned lock acquisition code](https://github.com/getsentry/crashpad/blob/e5040b878718f5c004d0ecfe1747642c72ddcd39/client/crash_report_database_generic.cc#L112-L121)
  calls `LoggingOpenFileForWrite` for exclusive report locks.

## Local fix

[The registered fix](../overlays/temporary/sentry-crashpad-lock.nix) replaces the
logging open call only at report-lock acquisition. It suppresses `EEXIST` there
and retains diagnostics for other failures. Exclusive creation, lock ownership,
busy return values, report contents, and crash reporting remain unchanged.

The selection in [packages.nix](../overlays/packages.nix) takes both Nix and its
Sentry dependency directly from `inputs.determinate.inputs.nix.packages`.
It patches Sentry inside that Determinate Nix package's component scope and
exports the result as `pkgs.nix`, preserving the dependency's curl customization.
Other Sentry consumers and Darwin's native Crashpad database are unaffected.

The [Determinate configuration module](../modules/shared/determinate.nix) selects
the overlaid package for `nix.package`. The upstream NixOS module otherwise
selects its flake input directly and bypasses the overlay. Evaluation checks
verify that both the system package and Nixd's `--nix-bin` use the selection.

## Validation and retirement

The behavioral test creates synthetic reports without crashing or uploading.
A child process attempts to read a report while the parent holds its lock. It
checks pending and completed reports, requires a busy result and empty stderr,
and verifies that the lock and report survive. A separate permission test
requires the real filesystem error to remain visible.

The unmodified dependency failed with the reported `File exists` diagnostic;
the patched dependency passed all three cases on x86_64 Linux.
An additional smoke test used the built Nix CLI and an isolated cache containing
a synthetic completed report with a held lock. Upstream emitted four error
lines; the patched CLI emitted none. Both commands succeeded and preserved the
held lock. Reporting remained enabled with a loopback-only endpoint.

```console
nix build --no-link path:.#checks.x86_64-linux.sentry-crashpad-lock
nix build --no-link path:.#checks.x86_64-linux.sentry-crashpad-lock-lifecycle
just temporary-fixes-check
```

The patch helper skips application if the exact fix is already present.
Unknown source changes stop the build without applying a partial patch.
The lifecycle check exercises initial application, skipping an existing fix,
and rejection of unfamiliar source.

There is no guessed version cutoff and no live upstream lookup during Nix
evaluation. The repository's revision guard still requires review when the
Determinate input changes. To assess a new pin, build its unmodified dependency
with the same behavioral test:

```console
nix build --no-link --impure --expr '
  let f = builtins.getFlake ("path:" + toString ./.);
  in f.nixosConfigurations.desktop.pkgs.nix.tests.crashpad-lock-upstream
'
```

This probe is expected to fail while the upstream bug remains. After an upstream
fix passes it, retire the registry entry, package selection, patch, and obsolete
checks together. Automatic skipping handles an identical backport; a differently
implemented upstream fix requires review and successful behavioral validation.
