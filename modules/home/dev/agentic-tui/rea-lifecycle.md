# Local process lifecycle

REA runs on demand on this workstation. Its global MCP registration is disabled
intentionally. Missing REA MCP tools are expected; do not run setup or enable a
global server to repair their absence.

Prefer the installed `rea` one-shot CLI. Select the corresponding command using
`rea --help` or its command help, then run it for the requested operation. Each
command owns its analysis session and exits afterward. Save complete JSON
Evidence to a task-selected file before inspecting smaller views. The MCP tool
names below describe operations; use the installed CLI's actual arguments.

Use the active harness's native browser controls for ordinary browser work.
In T3, follow its shared-browser routing. Use REA browser captures only when
the authorized analysis needs their specialized Evidence and the active
harness permits that route.

Follow the repository's workload and task-resource instructions before running
analysis. Use `codex-task run` for temporary commands that own child processes;
use `workstation-task` for heavy desktop work. Durable finite checks use
`workstation-job` with frozen inputs and one allocation. Task ownership and
workload admission are separate requirements; an allocated job runs its checks
directly without submitting another job.

If an operation requires a persistent MCP session, start `rea mcp` only inside a
task-owned client with an explicit lifetime. Keep it alive while requests or an
open analysis session need it. Close native sessions and export Evidence needed
after shutdown, then close the transport and wait for REA to exit. Put cleanup
in the client's `finally` path so completion, errors, cancellation, and input
EOF release its owned processes. Use bounded shutdown with TERM and a final
KILL fallback only for that client's owned processes. Preserve the session
while the active task or a requested follow-up depends on it, including during
pauses with no request in flight. Stop it on task completion or cancellation,
or after confirming no remaining work depends on its live state. Save needed
Evidence before shutdown. An idle process alone is not a completion signal;
keep ownership with the task rather than detaching a shared server.

Permanent MCP registration requires an explicit user request. The upstream
connection guide's registration-repair steps apply only to that chosen mode.
