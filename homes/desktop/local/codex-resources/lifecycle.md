# Task-owned resources

Keep persistent kernels, browser helpers, and MCP transports owned by the task
that needs them. Save needed results to files, release large temporary objects
after each analysis, and reset the task's Node/Python REPL when its work is
complete. Preserve session state while active work or a requested follow-up
still depends on it.

Run temporary helper servers and other commands that may leave child processes
with `codex-task run COMMAND [ARGS...]`. The service cleans remaining children
when its main command exits. Use `nix develop --command ...` inside that command
for project-specific dependencies. Persistent applications belong in declared
user services instead. Keep using `workstation-task` for heavy builds and
checks; `codex-task` owns lifetimes and does not replace the workload queue.

When a task completes or is cancelled, stop its temporary helpers and run
`codex-task finish` to stop services registered to the current Codex thread.
Check `codex-task list` when resuming work. Delegated workers close only the
resources they started; the coordinator runs `finish` after all work sharing
the thread is complete. Keep required background work running
until its owning task completes; sleeping state, process age, and low CPU use
are not completion signals. Native REPL and MCP tools need their own close or
reset operation; `codex-task finish` only owns services launched with this helper.
