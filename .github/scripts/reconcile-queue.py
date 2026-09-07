"""Admit passing bot PRs and dispatch CI suppressed by GITHUB_TOKEN.

Only GitHub API metadata is read. No PR files, artifacts, or commands are run.
"""

# Fixed GitHub CLI invocations use argv without a shell; progress goes to Actions logs.
# ruff: file-ignore[suspicious-subprocess-import, subprocess-without-shell-equals-true, print]
from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from typing import Any

REPOSITORY = os.environ["GH_REPO"]
WORKFLOWS = json.loads(os.environ["QUEUE_WORKFLOWS"])
ADMISSION = "Merge queue admission"
PAGE_SIZE = 100
GH = shutil.which("gh") or "/usr/bin/gh"


def api(path: str, method: str = "GET", data: object = None) -> Any:  # ruff: ignore[any-type]
    """Decode an arbitrary GitHub REST or GraphQL JSON response.

    Returns:
        The decoded response, or None for an empty response.

    """
    command = [GH, "api", path, "--method", method]
    if data is not None:
        command += ["--input", "-"]
    result = subprocess.run(
        command,
        input=json.dumps(data) if data is not None else None,
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout) if result.stdout.strip() else None


def graphql(query: str, **variables: str) -> dict[str, Any]:
    """Send a parameterized GraphQL operation and reject API errors.

    Returns:
        The data object returned by GitHub.

    Raises:
        RuntimeError: GitHub rejected the operation.

    """
    result = api("graphql", "POST", {"query": query, "variables": variables})
    if result.get("errors"):
        message = json.dumps(result["errors"])
        raise RuntimeError(message)
    return result["data"]


def admit(pr: dict[str, Any]) -> None:
    """Admit one eligible PR once its required checks pass."""
    trusted = pr["user"]["login"] == "dependabot[bot]" or (
        REPOSITORY == "nix-forge/nixpkgs-personal"
        and pr["user"]["login"] == "github-actions[bot]"
        and pr["head"]["ref"] == "automation/package-updates"
    )
    if not trusted or pr["draft"] or pr["head"]["repo"]["full_name"] != REPOSITORY:
        return
    number, sha = pr["number"], pr["head"]["sha"]
    state = graphql(
        "query($id:ID!) { node(id:$id) { ... on PullRequest { mergeQueueEntry { id } } } }",
        id=pr["node_id"],
    )["node"]
    if state["mergeQueueEntry"]:
        return
    # Once admitted, a rejected head needs a fix or deliberate requeue.
    # Never keep rebuilding the same failing merge group indefinitely.
    statuses = api(f"repos/{REPOSITORY}/commits/{sha}/status")["statuses"]
    if any(status["context"] == ADMISSION for status in statuses):
        print(f"PR #{number}: already admitted this head; leave rejection for review")
        return
    checks = subprocess.run(
        [
            GH,
            "pr",
            "checks",
            str(number),
            "--repo",
            REPOSITORY,
            "--required",
            "--json",
            "bucket",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    # CLI exit 1 also covers permission/API errors. Only a real check list
    # can mean a failing check; surface malformed output instead of hiding it.
    if not checks.stdout.strip().startswith("["):
        checks.check_returncode()
    if checks.returncode in {1, 8}:
        print(f"PR #{number}: required checks are not passing yet")
        return
    checks.check_returncode()
    required = json.loads(checks.stdout)
    if not required or any(
        check["bucket"] not in {"pass", "skipping"} for check in required
    ):
        return
    try:
        graphql(
            "mutation($id:ID!,$sha:GitObjectID!) { enqueuePullRequest(input:"
            "{pullRequestId:$id,expectedHeadOid:$sha}) { mergeQueueEntry { id } } }",
            id=pr["node_id"],
            sha=sha,
        )
    except (subprocess.CalledProcessError, RuntimeError) as error:
        # GitHub also enforces review, conflict, and branch rules here.
        print(
            f"PR #{number}: admission refused: {getattr(error, 'stderr', None) or str(error)}"
        )
        return
    api(
        f"repos/{REPOSITORY}/statuses/{sha}",
        "POST",
        {
            "state": "success",
            "context": ADMISSION,
            "description": "This PR head was admitted to the merge queue",
        },
    )
    print(f"PR #{number}: admitted {sha}")


def wait_for_source_run(run_id: str) -> None:
    """Wait briefly for the dispatch callback's own workflow to finish.

    Raises:
        ValueError: The supplied run ID is not an ASCII integer.

    """
    if not run_id:
        return
    if not run_id.isascii() or not run_id.isdecimal():
        message = "Source run ID must be an ASCII integer"
        raise ValueError(message)
    for _ in range(12):
        run = api(f"repos/{REPOSITORY}/actions/runs/{run_id}")
        if run["status"] == "completed":
            return
        time.sleep(5)
    print(f"Source run {run_id} is still running; reconcile other ready entries")


def main() -> None:
    """Reconcile open automation PRs, then start missing queue validation.

    Raises:
        subprocess.CalledProcessError: An API error other than a deleted ref occurred.

    """
    wait_for_source_run(os.environ.get("SOURCE_RUN_ID", ""))

    # Pagination is bounded by GitHub's repository PR limit, not a waiting loop.
    page = 1
    while True:
        pulls = api(
            f"repos/{REPOSITORY}/pulls?state=open&base=main&per_page={PAGE_SIZE}&page={page}"
        )
        for pr in pulls:
            admit(pr)
        if len(pulls) < PAGE_SIZE:
            break
        page += 1

    # GITHUB_TOKEN enqueue events do not start merge_group workflows. Explicit
    # dispatch is supported. Discover queue refs and validate their exact SHA.
    refs = api(f"repos/{REPOSITORY}/git/matching-refs/heads/gh-readonly-queue/main/")
    for entry in refs:
        try:
            dispatch_entry(entry)
        except subprocess.CalledProcessError as error:  # ruff: ignore[try-except-in-loop]
            # Each ref can disappear independently while GitHub advances the queue.
            if "HTTP 404" not in (error.stderr or ""):
                raise
            print(f"Queue ref disappeared: {entry['ref']}")


def dispatch_entry(entry: dict[str, Any]) -> None:
    """Start missing workflows for one queue ref if it still exists."""
    ref, sha = entry["ref"], entry["object"]["sha"]
    if not ref.startswith("refs/heads/gh-readonly-queue/main/"):
        return
    base = api(f"repos/{REPOSITORY}/git/commits/{sha}")["parents"][0]["sha"]
    validation_runs: list[dict[str, Any]] = []
    for workflow in WORKFLOWS:
        runs = api(
            f"repos/{REPOSITORY}/actions/workflows/{workflow}/runs?head_sha={sha}&per_page=1"
        )
        if runs["total_count"]:
            latest_run = runs["workflow_runs"][0]
            latest_run["queue_workflow"] = workflow
            validation_runs.append(latest_run)
            continue
        # The ref can disappear when another group merges. Do not dispatch
        # against a replacement commit after inspecting a different SHA.
        current = api(f"repos/{REPOSITORY}/git/ref/{ref.removeprefix('refs/')}")
        if current["object"]["sha"] != sha:
            break
        payload = {"ref": ref.removeprefix("refs/heads/")}
        if workflow == "dependency-review.yml":
            payload["inputs"] = {"base_ref": base, "head_ref": sha}
        if REPOSITORY == "nix-forge/nixpkgs-personal" and workflow == "ci.yml":
            payload["inputs"] = {"base_sha": base}
        api(
            f"repos/{REPOSITORY}/actions/workflows/{workflow}/dispatches",
            "POST",
            payload,
        )
        print(f"Dispatched {workflow} for {sha}")
    publish_dispatch_results(ref, sha, validation_runs)


def read_statuses(sha: str) -> dict[str, Any]:
    """Read the latest commit status for every context.

    Returns:
        Statuses indexed by their exact context names.

    """
    statuses: list[dict[str, Any]] = []
    page = 1
    while True:
        batch = api(
            f"repos/{REPOSITORY}/commits/{sha}/status?per_page={PAGE_SIZE}&page={page}"
        )["statuses"]
        statuses.extend(batch)
        if len(batch) < PAGE_SIZE:
            break
        page += 1
    return {status["context"]: status for status in reversed(statuses)}


def workflow_set_passed(sha: str, runs: list[dict[str, Any]]) -> bool:
    """Require the complete configured workflow set on the inspected commit.

    Returns:
        Whether every workflow finished successfully on this SHA.

    """
    return len(runs) == len(WORKFLOWS) and all(
        run["head_sha"] == sha
        and run["status"] == "completed"
        and run["conclusion"] == "success"
        for run in runs
    )


def latest_dispatch_jobs(
    sha: str, runs: list[dict[str, Any]]
) -> list[dict[str, Any]] | None:
    """Read dispatch jobs and reject newer runs or attempts.

    Returns:
        Completed jobs on this commit, or None when the evidence changed.

    """
    jobs: list[dict[str, Any]] = []
    for run in runs:
        page = 1
        while True:
            batch = api(
                f"repos/{REPOSITORY}/actions/runs/{run['id']}/jobs"
                f"?filter=latest&per_page={PAGE_SIZE}&page={page}"
            )["jobs"]
            jobs.extend(batch)
            if len(batch) < PAGE_SIZE:
                break
            page += 1
        # A separate dispatch or rerun can replace the evidence being inspected.
        fresh = api(
            f"repos/{REPOSITORY}/actions/workflows/{run['queue_workflow']}/runs"
            f"?head_sha={sha}&per_page=1"
        )["workflow_runs"]
        current = fresh[0] if fresh else {}
        expected = {
            key: run[key]
            for key in ("id", "run_attempt", "status", "conclusion", "head_sha")
        }
        if any(current.get(key) != value for key, value in expected.items()):
            return None
    if any(job["head_sha"] != sha or job["status"] != "completed" for job in jobs):
        return None
    return [job for job in jobs if job["name"] != "Queue completion callback"]


def invalidate_results(
    ref: str, sha: str, latest: dict[str, Any], successful: set[str] | None = None
) -> None:
    """Invalidate old adapter results absent from the latest successful jobs."""
    for status in latest.values():
        if status.get("description", "").startswith("Mirrored queue job") and (
            successful is None or status["context"] not in successful
        ):
            publish_status(
                ref,
                sha,
                latest,
                {
                    "context": status["context"],
                    "state": "pending",
                    "target_url": status["target_url"],
                },
            )


def publish_dispatch_results(ref: str, sha: str, runs: list[dict[str, Any]]) -> None:
    """Expose verified dispatch results to the merge queue's status evaluator."""
    dispatched = [run for run in runs if run["event"] == "workflow_dispatch"]
    if not dispatched:
        return
    latest = read_statuses(sha)
    if not workflow_set_passed(sha, runs):
        invalidate_results(ref, sha, latest)
        return
    jobs = latest_dispatch_jobs(sha, dispatched)
    if not jobs:
        invalidate_results(ref, sha, latest)
        return
    successful = {job["name"] for job in jobs if job["conclusion"] == "success"}
    invalidate_results(ref, sha, latest, successful)
    for job in jobs:
        # A skipped job is not evidence that validation ran. Never invent a pass.
        if job["conclusion"] == "success":
            publish_status(
                ref,
                sha,
                latest,
                {
                    "context": job["name"],
                    "state": "success",
                    "target_url": job["html_url"],
                },
            )


def publish_status(
    ref: str,
    sha: str,
    latest: dict[str, Any],
    result: dict[str, str],
) -> None:
    """Publish one actual job result once, while its queue ref still matches."""
    name, state, target_url = result["context"], result["state"], result["target_url"]
    previous = latest.get(name, {})
    if previous.get("state") == state and previous.get("target_url") == target_url:
        return
    current = api(f"repos/{REPOSITORY}/git/ref/{ref.removeprefix('refs/')}")
    if current["object"]["sha"] != sha:
        return
    api(
        f"repos/{REPOSITORY}/statuses/{sha}",
        "POST",
        {
            "context": name,
            "state": state,
            "target_url": target_url,
            "description": "Mirrored queue job result"
            if state == "success"
            else "Mirrored queue job awaiting validation",
        },
    )
    print(f"Reported {name}: {state} for {sha}")


if __name__ == "__main__":
    main()
