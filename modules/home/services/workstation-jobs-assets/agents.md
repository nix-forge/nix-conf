
# Durable finite jobs

Use `workstation-job submit --owner TASK --key UNIQUE_REQUEST --source IMMUTABLE_REFERENCE
--profile auto --memory-mib MIB --timeout SECONDS -- COMMAND ARGS...` for durable
finite checks. Submit on the execution host over SSH; do not hold a local workload
lock while waiting remotely. Record the returned ID in the task brief. Freeze
source and inputs using the project's own procedure before submission.

Reuse the same owner/key and identical specification to reconcile a lost reply.
Never submit duplicates while an existing job is queued or running. Inside a
job, run inner checks in its current allocation; do not submit/wait another
`workstation-job` or delegate its payload into another service. Use
`workstation-job status ID`, `log ID`, and `wait ID`; waiting does not cancel the
job. Admission or a queue ID is not a passing result. Verify terminal exit status,
expected cases, source identity, resource receipt, and drained execution scope.

Declare the whole job's memory and deadline. Auto routing defaults to bounded:
use it for compiler checks, test suites and finite host work. Only an explicitly
declared short deadline and a memory request fitting feedback select feedback.
Use `--requires-daemon` (or explicit `--profile daemon`) for shared Nix daemon
builds; preparation using that daemon and subsequent confined checks can be
separate jobs with separately frozen inputs. Desktop bounded jobs hide the
shared daemon. Requests beyond bounded capacity require placement review;
automatic routing never grants daemon access to fit an oversized request.
Feedback is a tiny diagnostic tier with a two-minute ceiling. Keep complete
acceptance checks in bounded or daemon allocations, even if one diagnostic fits
feedback. Review the executor's capacity decision and limit events when a job
fails; request a suitable new bounded attempt instead of repeating a throttled
feedback attempt. Existing attempts retain their immutable profile and limits.
Native macOS memory watchdogs are best effort, not cgroup limits. Preserve compiler
parallelism and all required checks. Capacity failures are preflight failures;
OOM, timeout, interrupted jobs and payload exit75 remain failed attempts. Retry
only explicitly with a new attempt key after addressing the cause. Never replay
financial, deployment or other non-idempotent work automatically.

After daemon recovery, unclaimed queued work can resume if its original group
was running and no interrupted execution is present. Manual pauses survive.
Inspect `workstation-job doctor` and reconcile interrupted owned processes before
`resume-queued --acknowledge-interrupted`. Interrupted jobs stay failed; each
immutable execution has a durable claim that prevents a second payload launch. Persistent services stay in
systemd/launchd. Temporary helpers use `codex-task run` and their owner's finish
procedure. Do not clean up another task's state or stop Windows or active work.
