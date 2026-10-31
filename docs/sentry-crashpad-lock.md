# Quiet Crashpad report-lock contention

Linux Determinate Nix uses Sentry Native's Crashpad backend. Concurrent CLI
processes can inspect the same crash report. An existing exclusive report lock
means the report is busy; it must not produce a filesystem-error diagnostic.
Other failures, including permission errors, must remain visible.

## Upstream repair and local retirement

The previous Sentry Native 0.13.5 dependency called `LoggingOpenFileForWrite`
before returning the busy status. A local repair suppressed only `EEXIST` at
report-lock acquisition, preserving exclusive creation and other diagnostics.
Its [paired native regression](https://github.com/nix-forge/nix-conf/actions/runs/38311793956/job/115019580250)
reproduced the upstream diagnostic and verified the repaired behavior.

Determinate input `c362c7c911ecf67570b2f19565b1bacc37de9ce8` selects nested Nix
`9993a12bd434f653d5081b9b35f50900412fece8` and Sentry Native 0.17.4. Its
[Crashpad source](https://github.com/getsentry/crashpad/blob/493151b224a6536bcedc3467d042863a063addc4/client/crash_report_database_generic.cc#L118-L123)
already contains the same nonlogging open and conditional error report.
The [unmodified native check](https://github.com/nix-forge/nix-conf/actions/runs/41226706466/job/124612258965)
passes quiet pending/completed contention and visible permission-error cases.

The local patch, application helper, registry records and input-module adapter
are therefore retired. The normal upstream module remains the sole owner of
`nix.package` and Nixd's `--nix-bin`. The [module check](../tests/nix/determinate-module.nix)
requires equality with the upstream package, normal module priority and the
expected daemon command. Darwin's separate sandbox-test policy remains active.

## Retained behavior check

The [probe](../tests/nix/sentry/crashpad-lock.cc) creates synthetic reports without
crashing or uploading. A child attempts to read a report while its parent holds
the lock. Pending and completed cases must return busy with empty stderr and
preserve both report and lock. A separate permission case must retain the real
filesystem diagnostic.

The check selects Sentry directly from the locked Determinate CLI's actual build
dependencies, including its existing curl customization. It stops if that
dependency disappears or becomes ambiguous.

```console
nix build --no-link path:.#checks.x86_64-linux.sentry-crashpad-lock
```

This isolated dependency check does not build or activate the desktop system.
