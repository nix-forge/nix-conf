# Merge queue operations

Passing Dependabot PRs enter the protected main merge queue after workflow
completion. The package updater is also eligible in nixpkgs-personal.
The reconciler reads API metadata and executes only its default branch script.
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

Run regression tests with `python3 -m unittest discover -s .github/tests`.
