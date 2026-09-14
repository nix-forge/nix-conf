# Coordinating agent work

For substantial work, the coordinating agent owns one task brief, delegation,
integration, and verification. Start from [the task template](../templates/task.md)
and draft it from the request and repository evidence. Ask the user for decisions
that affect the result and cannot be resolved from available sources. Reuse
settled decisions. A small edit can keep its requirements in the conversation.

Store redacted local briefs under `.scratch/<task>/spec.md`, following
[research guidance](research.md). Update the same brief when scope changes.
Give each worker and reviewer the accepted outcome and completion criteria.
Ignored drafts do not appear automatically in another worktree or machine;
pass their contents or provide a reviewed copy explicitly.

For desktop evaluation, builds, or checks, pass the
[workload-runner requirement](../desktop-memory-management.md) to every worker.
Independent worktrees share the desktop user's queue. Coordinate remote/root
jobs separately because wrapping a local deployment client does not wrap its
remote evaluation process.

## Parallel work

Delegate independent research or review when it reduces the coordinator's work.
Start with at most two concurrent implementation tasks and increase only when
their ownership and dependencies are clear. Keep dependent edits with one owner.
Use separate worktrees for independent writers. A read-only helper may share a
checkout, but reviews need a fixed commit or captured patch.

Each assignment identifies the owning repository, exact starting commit,
deliverable, owned paths, dependencies, and verification. The coordinator supplies
any required uncommitted changes explicitly. Check each submodule's recorded
revision and working state before using it; a root worktree does not make its
submodules ready or include unpublished submodule work.

Each worker returns the patch or commit, changed files, check results, and any
unmet requirement. The coordinator resolves overlap, integrates the work, and
runs the required checks on the combined result. Preserve the
[repository boundaries and build placement](../../CONTRIBUTING.md).

## Review and handoff

For meaningful changes, supply a fresh reviewer with the brief and a fixed diff.
Include staged, unstaged, new files, and submodule patches when they are in scope.
Use [the workflow guide](workflows.md#review-inputs) to distinguish standards
findings from unmet requirements. A separate reviewer is useful scrutiny, not
proof of correctness.

Before handing work to another session, update the brief with completed work,
settled decisions and reasons, the patch or commit, checks and observed results,
remaining requirements, and the next action and owner. Keep personal context and
raw output in private storage under [the publication policy](../publication.md).

## Model effort and feedback

Use `codex --profile routine` to try Astra with medium reasoning on clear tasks;
use `codex --profile deep` for difficult diagnosis, design, or review. Profiles
change model and effort only. The desktop model picker remains independently
editable. Keep explicit user choices and raise effort when it prevents rework.

For workflow comparisons, record briefing time, later clarification requests,
review and repair time, elapsed completion time, and defects. Include human time
only when measured or supplied by the user. Keep acceptance checks fixed and
change one workflow choice at a time. These profiles and the initial writer limit
are trial defaults, not measured productivity claims.
