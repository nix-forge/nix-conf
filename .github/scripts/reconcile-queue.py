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


def main() -> None:
    """Reconcile open automation PRs, then start missing queue validation.

    Raises:
        subprocess.CalledProcessError: An API error other than a deleted ref occurred.

    """
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
    for workflow in WORKFLOWS:
        runs = api(
            f"repos/{REPOSITORY}/actions/workflows/{workflow}/runs?head_sha={sha}&per_page=1"
        )
        if runs["total_count"]:
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


if __name__ == "__main__":
    main()
