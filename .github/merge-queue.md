# Merge queue operations

Passing Dependabot PRs enter the protected main merge queue after workflow
completion. The package updater is also eligible in nixpkgs-personal.
The reconciler reads API metadata and executes its pinned shared action.
It owns automatic admission; no separate auto-merge workflow is needed.
Changes under `.github/`, `actions/`, `scripts/` and `workflow-templates/`
require maintainer admission, including files renamed out of those paths.
Forks, drafts, failing checks, missing checks, changed heads and GitHub review
requirements cannot be bypassed by queue admission.

GitHub suppresses merge_group workflow events after GITHUB_TOKEN mutations.
The reconciler explicitly dispatches missing required workflows against the
queue ref, and dependency review compares main with the queue commit. Existing
runs are reused, including failed runs. A twenty-minute schedule recovers missed
events and queue refs that were not yet available during the original run.

The Merge queue admission commit status records one automatic admission per PR
head. If a group fails, fix the PR and push a new commit. For a confirmed transient
failure, rerun failed jobs or deliberately requeue the unchanged PR. Automation
never repeatedly rebuilds the same rejected head. A maintainer may run Reconcile
merge queue manually after enqueueing to start any missing queue workflows.

Required checks and merge queue rules remain enforced. CI runs on PRs and merge
groups; it does not repeat the same full build after a successful queued merge.
CodeQL retains its main-branch scan, and documentation retains its publish job.

Shared queue regression tests live in [nix-forge/ci](https://github.com/nix-forge/ci).
Run repository-specific selection tests separately when present.

macOS jobs use the supported macos-26 image. nix-seal retains its legacy
macos-14 matrix labels only as required-check identifiers; runs-on selects
macos-26. This avoids leaving existing branch protections waiting for renamed
checks during the runner migration. GitHub retires macos-14 on November 2, 2026.

Dispatched checks can be absent from GitHub's merge-queue status summary even
when their check suites succeeded. The trusted reconciler reports completed,
successful dispatch jobs as same-name commit statuses, linked to the actual job.
It waits for the full workflow set, verifies the latest attempt and live queue
SHA, and never reports skipped or missing jobs as successful. A newer incomplete
attempt invalidates earlier adapter statuses. Required contexts and the expected
GitHub Actions app remain unchanged.
