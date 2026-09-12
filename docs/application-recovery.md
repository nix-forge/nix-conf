# Application recovery and service health

The [application recovery module](../modules/nixos/services/application-recovery/default.nix)
lets the application owner declare a consistent export, backup transport, restore
and semantic check. Import the module and configure
`services.applicationRecovery.applications.<name>`. No recipe or destination is
enabled implicitly. The existing [cold backups](desktop-storage-operations.md)
remain the attended route for complete VM and container trees.

Each application declares five shell hooks, with required tools in `packages`.
Credentials must come from protected runtime files, never Nix strings. Hooks get
fresh private `RECOVERY_EXPORT` and `RECOVERY_TARGET` directories. They must fail
when their operation cannot complete; a successful no-op is not useful evidence.

| Hook | Required behavior |
| --- | --- |
| `export` | Write a consistent database export or stopped-writer snapshot into `RECOVERY_EXPORT`. |
| `backup` | Persist that export to a provisioned destination. Use a stable application tag because scratch paths change. |
| `recover` | Fetch an identified backup into `RECOVERY_EXPORT`; fail when its selection is absent or ambiguous. |
| `restore` | Restore the export into the disposable `RECOVERY_TARGET`. |
| `check` | Query restored application data and verify required semantics, relationships and durable artifacts. |

Start `application-recovery-<name>-backup.service` for export and backup. The
runner stops the declared `units` that were active and restarts them after success
or failure. Inactive services remain inactive. Every restart is attempted even if
another restart fails, and any restart failure prevents a success receipt. Hooks
have individual `timeoutSeconds` limits. Hooks must finish synchronously; a hook
that leaves child processes in its process group fails. Hooks must not create new
sessions, which escape process-group cleanup. Cancellation terminates the current hook
and attempts writer recovery. SIGKILL, host loss and a broken service can still
require operator repair.

The owner must prevent socket, timer, container and guest activation during the
export window. Stopping a daemon alone does not stop a guest or exclude another
administrator's writes. Keep such applications on the existing rescue-mode cold
backup until a recipe establishes their own consistency boundary. Recipes do not
schedule production stops automatically.

Start `application-recovery-<name>-drill.service` to fetch, restore and check a
backup. The systemd unit exposes the system and home trees read-only, permits
writes in its own private state directory, and removes capabilities. The runner
serializes backup and drill for one application and deletes scratch data on both
success and failure. These controls do not make an arbitrary hook safe to copy
into an attended production restoration command. Review the application's actual
restore procedure separately.

Receipts under `/var/lib/application-recovery/<name>/` distinguish the latest
attempt from the last successful backup or isolated drill. They contain completion
time, result, action and a hash of the declared policy. A failed newer attempt
never replaces the preceding successful receipt. Monitor both the success age and
the latest attempt so a recent success cannot conceal a failed retry. These
receipts do not satisfy the existing attended `recovery-drill` backup requirement.

## Health probes and delivery

The existing storage monitor accepts additional
`hardware.storage.encryptedRoot.health.probes` entries. Each public label declares
an absolute `command` argument list, a `timeoutSeconds` bound, a `receipt` path, or
both. Receipts contain `completed` Unix seconds and may include `result`, which
must be `success`. `maxAgeSeconds` controls freshness. Missing, malformed,
non-finite and future timestamps produce an alert. Probe output remains private;
notifications contain the declared label only.

For an application recipe, add one receipt probe for `backup-success.json` with
its backup freshness limit, another for `drill-success.json`, and checks for
`backup-attempt.json` and `drill-attempt.json` to expose failed latest attempts.
Use a suitably longer age for the drill and attempt records. A service-active
probe should use `systemctl is-active --quiet <unit>`; a completed periodic job
needs freshness evidence rather than an always-active requirement.

`notificationCommand` accepts an absolute command and arguments. It receives one
JSON object on stdin with `event` equal to `warning`, `recovery` or `test`, plus a
`messages` list. It must exit successfully only after the channel accepts the
message. Commands have a bounded deadline and must complete synchronously.
Unfinished children cause failure and process-group cleanup; hooks must not create
new sessions. Use runtime credentials in the hook. `sudo desktop-storage-status
test-delivery` sends a test without acknowledging the current alert state.

The independent `desktop-storage-delivery` timer runs without a desktop session
and detects stale collector output. With no command configured or when delivery
fails, `/var/lib/desktop-storage/delivery/pending.json` retains the pending event.
Successful warning and recovery transitions deduplicate; failed sends retry. The
desktop notifier retains its separate delivery state. Configure and test a real
channel before relying on notifications while logged out.

## Validation limits

The [Restic fixture](../tests/storage/test_application_recovery.py) restores a
SQLite database containing committed WAL records after deleting the source. It
also checks a VM definition, disk-state bytes, firmware and vTPM fixture state.
These artifacts test backup completeness and generation identity. They do not
prove a real VM boots or that its TPM keys decrypt real guest storage.

The [NixOS fixture](../tests/recovery/application-recovery.nix) tests generated
service lifecycle, writer restart after export failure, restoration after source
deletion and rejection of writes to live directories during a drill. Delivery
tests use local commands; they do not establish that a remote provider or device
received a notification. Provisioned backup media, live application drills and an
external notification channel remain separate operational requirements.
