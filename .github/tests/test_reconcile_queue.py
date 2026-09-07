"""Exercise queue admission and GITHUB_TOKEN dispatch without remote writes."""

# unittest keeps these runner checks free of third-party dependencies.
# subprocess is used only for a fake CompletedProcess and mocked runner.
# ruff: file-ignore[pytest-unittest-assertion, pytest-unittest-raises-assertion, suspicious-subprocess-import]
from __future__ import annotations

import importlib.util
import json
import os
import re
import subprocess
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

os.environ.setdefault("GH_REPO", "nix-forge/example")
os.environ.setdefault("QUEUE_WORKFLOWS", '["ci.yml", "dependency-review.yml"]')
spec = importlib.util.spec_from_file_location(
    "queue", Path(__file__).parents[1] / "scripts" / "reconcile-queue.py"
)
if spec is None or spec.loader is None:
    message = "Unable to load the queue reconciler"
    raise ImportError(message)
queue = importlib.util.module_from_spec(spec)
spec.loader.exec_module(queue)


class ReconcileTests(unittest.TestCase):
    """Keep CI and queue failures observable without executing PR code."""

    def setUp(self) -> None:
        """Reset the in-memory GitHub API fixtures."""
        self.pr: dict[str, Any] = {
            "user": {"login": "dependabot[bot]"},
            "draft": False,
            "number": 7,
            "node_id": "PR_7",
            "head": {
                "sha": "head",
                "ref": "dependabot/example",
                "repo": {"full_name": queue.REPOSITORY},
            },
        }
        self.statuses: list[dict[str, Any]] = []
        self.refs: list[dict[str, Any]] = []
        self.existing_runs = 0
        self.writes: list[tuple[str, Any]] = []

    def api(self, path: str, method: str = "GET", data: object = None) -> Any:  # ruff: ignore[any-type, too-many-return-statements]
        """Record writes and serve controlled API responses.

        Returns:
            A fixture matching the requested endpoint.

        Raises:
            AssertionError: An unexpected endpoint was requested.

        """
        if method != "GET":
            self.writes.append((path, data))
            return None
        if "/pulls?" in path:
            return [self.pr]
        if path.endswith("/status"):
            return {"statuses": self.statuses}
        if "matching-refs" in path:
            return self.refs
        if "/runs?" in path:
            return {
                "total_count": self.existing_runs,
                "workflow_runs": [{"event": "merge_group"}],
            }
        if "/git/commits/" in path:
            return {"parents": [{"sha": "base"}]}
        if "/git/ref/" in path:
            return {"object": {"sha": "group"}}
        raise AssertionError(path)

    def run_queue(self, check_code: int = 0) -> Any:  # ruff: ignore[any-type]
        """Run reconciliation with a simulated required-check result.

        Returns:
            The GraphQL mock for assertions about admission.

        """
        result = subprocess.CompletedProcess([], check_code, '[{"bucket":"pass"}]')
        with (
            patch.object(queue, "api", side_effect=self.api),
            patch.object(
                queue, "graphql", return_value={"node": {"mergeQueueEntry": None}}
            ) as graphql,
            patch.object(queue.subprocess, "run", return_value=result),
        ):
            queue.main()
        return graphql

    def test_pending_checks_do_not_poll_or_enqueue(self) -> None:
        """Verify pending checks do not poll or enqueue."""
        graphql = self.run_queue(check_code=8)
        self.assertEqual(graphql.call_count, 1)
        self.assertEqual(self.writes, [])

    def test_failed_checks_do_not_enqueue(self) -> None:
        """Verify failed checks do not enqueue."""
        self.assertEqual(self.run_queue(check_code=1).call_count, 1)
        self.assertEqual(self.writes, [])

    def test_fork_does_not_reach_checks_or_mutations(self) -> None:
        """Verify fork does not reach checks or mutations."""
        self.pr["head"]["repo"]["full_name"] = "attacker/example"
        self.assertEqual(self.run_queue().call_count, 0)
        self.assertEqual(self.writes, [])

    def test_rejected_head_is_not_requeued_forever(self) -> None:
        """Verify rejected head is not requeued forever."""
        self.statuses = [{"context": queue.ADMISSION}]
        self.assertEqual(self.run_queue().call_count, 1)
        self.assertEqual(self.writes, [])

    def test_admission_is_bound_to_reviewed_head(self) -> None:
        """Verify admission is bound to reviewed head."""
        graphql = self.run_queue()
        self.assertEqual(graphql.call_args.kwargs, {"id": "PR_7", "sha": "head"})
        self.assertEqual(self.writes[0][1]["context"], queue.ADMISSION)

    def test_missing_merge_group_events_dispatch_exact_queue_commit(self) -> None:
        """Verify missing merge group events dispatch exact queue commit."""
        self.pr["draft"] = True
        self.refs = [
            {
                "ref": "refs/heads/gh-readonly-queue/main/pr-7-base",
                "object": {"sha": "group"},
            }
        ]
        self.run_queue()
        self.assertEqual(len(self.writes), 2)
        self.assertEqual(self.writes[0][1], {"ref": "gh-readonly-queue/main/pr-7-base"})
        self.assertEqual(
            self.writes[1][1]["inputs"], {"base_ref": "base", "head_ref": "group"}
        )

    def test_existing_queue_runs_are_not_duplicated(self) -> None:
        """Verify existing queue runs are not duplicated."""
        self.pr["draft"] = True
        self.refs = [
            {
                "ref": "refs/heads/gh-readonly-queue/main/pr-7-base",
                "object": {"sha": "group"},
            }
        ]
        self.existing_runs = 1
        self.run_queue()
        self.assertEqual(self.writes, [])

    def test_admission_error_does_not_stop_dispatch(self) -> None:
        """Verify a GraphQL refusal leaves existing queue work eligible."""
        result = subprocess.CompletedProcess([], 0, '[{"bucket":"pass"}]')
        with (
            patch.object(queue, "api", side_effect=self.api),
            patch.object(
                queue,
                "graphql",
                side_effect=[
                    {"node": {"mergeQueueEntry": None}},
                    RuntimeError("head changed"),
                ],
            ),
            patch.object(queue.subprocess, "run", return_value=result),
        ):
            queue.main()
        self.assertEqual(self.writes, [])

    def test_disappearing_ref_does_not_stop_other_groups(self) -> None:
        """Verify deleting one queue ref does not starve later groups."""
        self.pr["draft"] = True
        self.refs = [{"ref": "first"}, {"ref": "second"}]
        error = subprocess.CalledProcessError(1, [], stderr="HTTP 404")
        with (
            patch.object(queue, "api", side_effect=self.api),
            patch.object(
                queue, "dispatch_entry", side_effect=[error, None]
            ) as dispatch,
        ):
            queue.main()
        self.assertEqual(dispatch.call_count, len(self.refs))


class DispatchResultTests(unittest.TestCase):
    """Report real dispatch jobs without promoting missing or stale evidence."""

    def setUp(self) -> None:
        """Create a successful dispatch and one native merge-group run."""
        self.ref = "refs/heads/gh-readonly-queue/main/pr-7-base"
        self.dispatch_run: dict[str, Any] = {
            "id": 1,
            "event": "workflow_dispatch",
            "head_sha": "group",
            "status": "completed",
            "conclusion": "success",
            "run_attempt": 1,
            "queue_workflow": "ci.yml",
        }
        self.other: dict[str, Any] = {
            **self.dispatch_run,
            "id": 2,
            "event": "merge_group",
        }
        self.jobs: list[dict[str, Any]] = [
            {
                "name": "Lint",
                "head_sha": "group",
                "status": "completed",
                "conclusion": "success",
                "html_url": "https://github.com/job/1",
            }
        ]
        self.statuses: list[dict[str, Any]] = []
        self.writes: list[dict[str, Any]] = []
        self.current = self.dispatch_run.copy()
        self.current_sha = "group"

    def api(self, path: str, method: str = "GET", data: object = None) -> Any:  # ruff: ignore[any-type]
        """Serve run and job metadata and retain published status payloads.

        Returns:
            The requested fixture.

        Raises:
            AssertionError: An unexpected endpoint was requested.

        """
        if method == "POST":
            if not isinstance(data, dict):
                raise AssertionError(path)
            self.writes.append(data)
            return None
        if path.endswith("/status") or "/status?" in path:
            return {"statuses": self.statuses}
        if "/jobs?" in path:
            return {"jobs": self.jobs}
        if "/actions/workflows/ci.yml/runs?" in path:
            return {"workflow_runs": [self.current]}
        if "/git/ref/" in path:
            return {"object": {"sha": self.current_sha}}
        raise AssertionError(path)

    def report(self, runs: list[dict[str, Any]] | None = None) -> None:
        """Run the adapter against the selected API fixtures."""
        with patch.object(queue, "api", side_effect=self.api):
            queue.publish_dispatch_results(
                self.ref,
                "group",
                runs if runs is not None else [self.dispatch_run, self.other],
            )

    def test_callback_is_not_a_validation_status(self) -> None:
        """A failed notification must not invalidate successful validation jobs."""
        self.jobs.append({
            **self.jobs[0],
            "name": "Queue completion callback",
            "conclusion": "failure",
        })
        self.report()
        self.assertEqual([write["context"] for write in self.writes], ["Lint"])

    def test_success_links_the_exact_completed_job(self) -> None:
        """Only the successful dispatch job becomes a linked commit status."""
        self.report()
        self.assertEqual(len(self.writes), 1)
        self.assertEqual(self.writes[0]["context"], "Lint")
        self.assertEqual(self.writes[0]["state"], "success")
        self.assertEqual(self.writes[0]["target_url"], self.jobs[0]["html_url"])

    def test_missing_workflow_cannot_report_success(self) -> None:
        """An incomplete workflow set leaves validation pending."""
        self.report([self.dispatch_run])
        self.assertEqual(self.writes, [])

    def test_pending_or_failed_workflow_cannot_report_success(self) -> None:
        """Other required validation must finish successfully first."""
        self.other["conclusion"] = "failure"
        self.report()
        self.assertEqual(self.writes, [])

    def test_skipped_or_missing_jobs_never_become_success(self) -> None:
        """A skipped or absent job provides no passing evidence."""
        self.jobs[0]["conclusion"] = "skipped"
        self.report()
        self.jobs = []
        self.report()
        self.assertEqual(self.writes, [])

    def test_job_from_another_commit_is_rejected(self) -> None:
        """Only the inspected queue commit can supply job results."""
        self.jobs[0]["head_sha"] = "different"
        self.report()
        self.assertEqual(self.writes, [])

    def test_changed_queue_ref_is_not_updated(self) -> None:
        """A changed ref cannot receive stale success statuses."""
        self.current_sha = "replacement"
        self.report()
        self.assertEqual(self.writes, [])

    def test_newer_attempt_invalidates_previous_success(self) -> None:
        """A rerun cannot retain the adapter result of an earlier attempt."""
        self.statuses = [
            {
                "context": "Lint",
                "state": "success",
                "target_url": self.jobs[0]["html_url"],
                "description": "Mirrored queue job result",
            }
        ]
        self.current["run_attempt"] = 2
        self.current["status"] = "in_progress"
        self.report()
        self.assertEqual([item["state"] for item in self.writes], ["pending"])

    def test_separate_newer_run_invalidates_previous_success(self) -> None:
        """A separate newer dispatch cannot inherit an older run's pass."""
        self.statuses = [
            {
                "context": "Lint",
                "state": "success",
                "target_url": self.jobs[0]["html_url"],
                "description": "Mirrored queue job result",
            }
        ]
        self.current["id"] = 3
        self.report()
        self.assertEqual([item["state"] for item in self.writes], ["pending"])

    def test_existing_identical_result_is_not_republished(self) -> None:
        """Repeated recovery calls reuse the same result."""
        self.statuses = [
            {
                "context": "Lint",
                "state": "success",
                "target_url": self.jobs[0]["html_url"],
                "description": "Mirrored queue job result",
            }
        ]
        self.report()
        self.assertEqual(self.writes, [])

    def test_missing_job_invalidates_previous_success(self) -> None:
        """A job absent from the latest attempt must not inherit a pass."""
        self.statuses = [
            {
                "context": "Removed",
                "state": "success",
                "target_url": "https://github.com/job/old",
                "description": "Mirrored queue job result",
            }
        ]
        self.report()
        self.assertEqual(self.writes[0]["context"], "Removed")
        self.assertEqual(self.writes[0]["state"], "pending")


class CompletionTests(unittest.TestCase):
    """Verify the callback cannot race its unfinished source workflow."""

    def test_all_validation_workflows_notify_after_their_jobs(self) -> None:
        """Every configured validator must explicitly report bot dispatch completion."""
        workflows = Path(__file__).parents[1] / "workflows"
        reconciler = (workflows / "reconcile-merge-queue.yml").read_text()
        configured = re.search(r"QUEUE_WORKFLOWS: '(.+)'", reconciler)
        if configured is None:
            self.fail("Missing queue workflow configuration")
        self.assertIn("SOURCE_RUN_ID: ${{ inputs.source_run_id }}", reconciler)
        for name in json.loads(configured[1]):
            content = (workflows / name).read_text()
            jobs, callback = content.split("  queue-completion:")
            job_names = set(
                re.findall(r"^  ([\w-]+):", jobs.split("\njobs:\n", 1)[1], re.MULTILINE)
            )
            needs = re.search(r"needs: \[([^]]+)\]", callback)
            if needs is None:
                self.fail("Missing callback dependencies")
            self.assertEqual(job_names, set(re.findall(r"[\w-]+", needs[1])), name)
            self.assertIn(
                "always() && github.event_name == 'workflow_dispatch'", callback
            )
            self.assertIn(
                "startsWith(github.ref, 'refs/heads/gh-readonly-queue/main/')", callback
            )
            self.assertIn(
                "gh workflow run reconcile-merge-queue.yml --ref main", callback
            )
            self.assertIn('source_run_id="$GITHUB_RUN_ID"', callback)
            self.assertNotIn("actions/checkout", callback)
            self.assertIn("continue-on-error: true", callback)
            self.assertIn("for attempt in 1 2 3", callback)

    def test_waits_for_source_completion(self) -> None:
        """A callback dispatch can arrive before GitHub finishes its source."""
        with (
            patch.object(
                queue,
                "api",
                side_effect=[{"status": "in_progress"}, {"status": "completed"}],
            ) as api,
            patch.object(queue.time, "sleep") as sleep,
        ):
            queue.wait_for_source_run("123")
        self.assertEqual(api.call_count, 2)
        sleep.assert_called_once_with(5)

    def test_wait_is_bounded(self) -> None:
        """A stuck source must not occupy a polling runner indefinitely."""
        with (
            patch.object(queue, "api", return_value={"status": "in_progress"}) as api,
            patch.object(queue.time, "sleep"),
        ):
            queue.wait_for_source_run("123")
        self.assertEqual(api.call_count, 12)

    def test_rejects_invalid_run_id(self) -> None:
        """Dispatch input cannot change the GitHub API path."""
        with patch.object(queue, "api") as api:
            with self.assertRaises(ValueError):
                queue.wait_for_source_run("../other")
            queue.wait_for_source_run("")
        api.assert_not_called()


if __name__ == "__main__":
    unittest.main()
