"""Exercise queue admission and GITHUB_TOKEN dispatch without remote writes."""

# unittest keeps these runner checks free of third-party dependencies.
# subprocess is used only for a fake CompletedProcess and mocked runner.
# ruff: file-ignore[pytest-unittest-assertion, suspicious-subprocess-import]
from __future__ import annotations

import importlib.util
import os
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
            return {"total_count": self.existing_runs}
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


if __name__ == "__main__":
    unittest.main()
