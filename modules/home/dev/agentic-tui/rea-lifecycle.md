# Local process lifecycle

REA runs on demand on this workstation. Its global MCP registration is disabled
intentionally. Missing REA MCP tools are expected; do not run setup or enable a
global server to repair their absence.

Prefer the installed `rea` one-shot CLI. Select the corresponding command using
`rea --help` or its command help, then run it for the requested operation. Each
command owns its analysis session and exits afterward. Save complete JSON
Evidence to a task-selected file before inspecting smaller views. The MCP tool
names below describe operations; use the installed CLI's actual arguments.

If an operation requires a persistent MCP session, start `rea mcp` only inside a
task-owned client with an explicit lifetime. Keep it alive while requests or an
open analysis session need it. Close native sessions and export Evidence needed
after shutdown, then close the transport and wait for REA to exit. Put cleanup
in the client's `finally` path so completion, errors, cancellation, and input
EOF release its owned processes. Use bounded shutdown with TERM and a final
KILL fallback only for that client's owned processes. Do not launch a detached
server or leave one running between unrelated tasks. When work pauses without
a request in flight, save its Evidence and close the session rather than
retaining an idle server.

Permanent MCP registration requires an explicit user request. The upstream
connection guide's registration-repair steps apply only to that chosen mode.
