# Application recovery drills

The application recovery module creates manual backup and isolated restore-drill
services from application-owned hooks. A recipe defines a consistent export,
backup transport, recovery selection, restore operation and semantic check.
No production application is stopped until its backup service is explicitly run.

Read the [module and operational guide](https://github.com/nix-forge/nix-conf/blob/main/docs/application-recovery.md)
before declaring a recipe. The [generated options](options.md) describe the
configuration interface. Keep credentials in protected runtime files and provision
real backup destinations before enabling a recipe.

The disposable tests restore committed SQLite data through Restic after deleting
the original, and check that VM disk, definition, firmware and virtual TPM fixture
state belong to the same backup. The NixOS test checks service shutdown/restart
and prevents the drill from writing to live directories. These results cover the
fixtures; actual application recovery and a real guest boot need separate drills.

## Check health without a desktop session

The desktop collector also checks enabled network, DNS, login, SSH and Nix
services. Additional command and freshness probes can cover application receipts.
A successful process-activity probe establishes service availability only; it
does not prove a working application workflow.

An independent system timer delivers warnings and recovery transitions through an
operator-provided command. Failed or unconfigured delivery retains a pending
record. Configure a real channel, run its test-delivery command, and confirm
receipt from the destination before relying on alerts while logged out.

Use [validation records](validation.md) to keep fixture, native build, runtime and
real recovery evidence distinct.
