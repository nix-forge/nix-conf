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

The [module adapter](../overlays/temporary/determinate-sentry-module.nix) takes
Nix and its Sentry dependency directly from Determinate's pinned Nix input.
It patches Sentry inside that package's component scope, preserving the
dependency's curl customization, and passes the repaired input to Determinate's
upstream NixOS module factory.

The [input overrides](../overlays/inputs.nix) replace
`inputs.determinate.nixosModules.default` with this adapter before configuration
evaluation. The [Determinate configuration module](../modules/shared/determinate.nix)
keeps its normal import and needs no edits when the patch is retired.
Determinate's upstream module remains the sole owner of
`nix.package` and Nixd's `--nix-bin`. The repair needs no `mkForce` assignment or
global `pkgs.nix` replacement. Other Sentry consumers and Darwin's native
Crashpad database are unaffected.

Evaluation checks exercise the adapter with an ordinary package set, verify
normal module priority, and check both the system package and daemon command.

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
evaluation. Revision guards require review when either the Determinate module
input or its nested Nix input changes. To assess a new pin, build its unmodified
dependency with the same behavioral test:

```console
nix build --no-link --impure --expr '
  let f = builtins.getFlake ("path:" + toString ./.);
  in f.nixosConfigurations.desktop.config.nix.package.tests.crashpad-lock-upstream
'
```

This probe is expected to fail while the upstream bug remains. After an upstream
fix passes it, remove the Determinate replacement in `overlays/inputs.nix` and
retire both registry entries, the module adapter, patch, and obsolete checks
together. Automatic skipping handles an identical backport; a differently
implemented upstream fix requires review and successful behavioral validation.
