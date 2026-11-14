"""Exercise preservation and placement through the public worktree command."""

from __future__ import annotations

import json
import os
import re
import selectors
import shutil
import subprocess
import sys
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from collections.abc import Callable

SCRIPT = (
    Path(__file__).resolve().parents[2] / "modules/home/dev/scripts/dev_worktree.py"
)


def git(repo: Path, *args: str) -> str:
    """Run real Git against a disposable repository.

    Returns:
        Captured standard output.

    """
    return subprocess.run(
        ["git", "-C", str(repo), *args], check=True, capture_output=True, text=True
    ).stdout.strip()


@pytest.fixture
def workspace(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> tuple[Path, Callable]:
    """Create a clone with no operational remotes or inherited commit settings.

    Returns:
        The durable clone and the public CLI adapter.

    """
    for name in list(os.environ):
        if name.startswith("GIT_"):
            monkeypatch.delenv(name)
    monkeypatch.setenv("GIT_CONFIG_NOSYSTEM", "1")
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", str(tmp_path / "absent-gitconfig"))
    repo = tmp_path / "Developer" / "owner" / "example"
    repo.mkdir(parents=True)
    git(repo, "init", "--initial-branch=main")
    git(repo, "config", "user.name", "Fixture")
    git(repo, "config", "user.email", "fixture@example.invalid")
    git(repo, "config", "commit.gpgsign", "false")
    git(repo, "config", "core.hooksPath", str(tmp_path / "absent-hooks"))
    (repo / "tracked.txt").write_text("original\n")
    git(repo, "add", "tracked.txt")
    git(repo, "commit", "-m", "fixture")
    config = tmp_path / "policy.json"
    config.write_text(
        json.dumps({
            "developerRoot": str(tmp_path / "Developer"),
            "worktreeRoot": str(tmp_path / "Worktrees"),
            "stateDirectory": str(tmp_path / "state"),
            "repositories": [str(repo)],
        })
    )

    def cli(*args: str, success: bool = True) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--config", str(config), *args],
            capture_output=True,
            text=True,
            check=False,
        )
        if success:
            assert result.returncode == 0, result.stderr
        else:
            assert result.returncode != 0
        return result

    return repo, cli


def test_new_checkout_is_unique_and_does_not_copy_pending_work(
    workspace: tuple[Path, Callable],
) -> None:
    """Explicit bases isolate tasks while the canonical checkout remains dirty."""
    repo, cli = workspace
    (repo / "tracked.txt").write_text("pending\n")
    first = Path(cli("new", str(repo), "review", "--base", "main").stdout.strip())
    second = Path(cli("new", str(repo), "review", "--base", "main").stdout.strip())
    assert first != second
    assert "Worktrees/manual/local" in str(first)
    assert (first / "tracked.txt").read_text() == "original\n"
    assert (repo / "tracked.txt").read_text() == "pending\n"
    assert not git(first, "status", "--porcelain")


@pytest.mark.parametrize("task", ["../escape", "a/b", "--unsafe"])
def test_invalid_task_names_do_not_create_worktrees(
    workspace: tuple[Path, Callable], task: str
) -> None:
    """Path traversal and argument-shaped task names fail without mutations."""
    repo, cli = workspace
    before = git(repo, "worktree", "list", "--porcelain")
    cli("new", str(repo), task, "--base", "main", success=False)
    assert git(repo, "worktree", "list", "--porcelain") == before


@pytest.mark.parametrize(
    "kind", ["tracked", "untracked", "ignored", "unretained", "locked"]
)
def test_removal_preserves_unsaved_or_active_work(
    workspace: tuple[Path, Callable], kind: str
) -> None:
    """Every refusal leaves the checkout and its commit intact."""
    repo, cli = workspace
    path = Path(cli("new", str(repo), "task", "--base", "main").stdout.strip())
    if kind == "tracked":
        (path / "tracked.txt").write_text("pending")
    elif kind == "untracked":
        (path / "new.txt").write_text("pending")
    elif kind == "ignored":
        git(path, "config", "core.excludesFile", str(repo.parent / "ignores"))
        (repo.parent / "ignores").write_text("saved.local\n")
        (path / "saved.local").write_text("needed")
    elif kind == "unretained":
        (path / "tracked.txt").write_text("committed task")
        git(path, "commit", "-am", "unpublished")
    else:
        git(path, "worktree", "lock", "--reason", "active", str(path))
    before = git(path, "rev-parse", "HEAD")
    cli(
        "remove",
        str(path),
        "--apply",
        "--completed",
        "--retained-ref",
        "refs/heads/main",
        success=False,
    )
    assert path.exists()
    assert git(path, "rev-parse", "HEAD") == before


def test_removal_previews_then_requires_completion(
    workspace: tuple[Path, Callable],
) -> None:
    """A retained clean checkout is removed only after explicit completion."""
    repo, cli = workspace
    path = Path(cli("new", str(repo), "task", "--base", "main").stdout.strip())
    cli("remove", str(path), "--retained-ref", "refs/heads/main")
    assert path.exists()
    cli(
        "remove",
        str(path),
        "--apply",
        "--retained-ref",
        "refs/heads/main",
        success=False,
    )
    assert path.exists()
    cli(
        "remove",
        str(path),
        "--apply",
        "--completed",
        "--retained-ref",
        "refs/heads/main",
    )
    assert not path.exists()
    assert (repo / "tracked.txt").exists()


def test_app_owned_checkout_cannot_be_removed(workspace: tuple[Path, Callable]) -> None:
    """An application directory never becomes manually owned through its name."""
    repo, cli = workspace
    path = repo.parents[2] / "Worktrees/codex/task"
    git(repo, "worktree", "add", "--detach", str(path), "main")
    cli("remove", str(path), "--apply", "--completed", success=False)
    assert path.exists()


def test_move_preserves_dirty_files_and_git_links(
    workspace: tuple[Path, Callable],
) -> None:
    """Explicit migration preserves edits and records manual ownership externally."""
    repo, cli = workspace
    old = repo.parent / "example-task"
    git(repo, "worktree", "add", "--detach", str(old), "main")
    (old / "tracked.txt").write_text("dirty")
    (old / "untracked.txt").write_text("untracked")
    cli("move", str(old))
    assert old.exists()
    cli("move", str(old), "--apply", success=False)
    cli("move", str(old), "--apply", "--completed")
    trees = json.loads(cli("list").stdout)
    moved = Path(next(tree["worktree"] for tree in trees if tree["owner"] == "manual"))
    assert not old.exists()
    assert (moved / "tracked.txt").read_text() == "dirty"
    assert (moved / "untracked.txt").read_text() == "untracked"
    assert git(moved, "rev-parse", "HEAD") == git(repo, "rev-parse", "HEAD")


def test_inventory_reports_missing_registrations_without_pruning(
    workspace: tuple[Path, Callable],
) -> None:
    """Doctor is read-only even when a worktree directory is missing."""
    repo, cli = workspace
    path = Path(cli("new", str(repo), "task", "--base", "main").stdout.strip())
    moved = path.with_name("relocated")
    path.rename(moved)
    before = git(repo, "worktree", "list", "--porcelain")
    assert any(not tree["exists"] for tree in json.loads(cli("doctor").stdout))
    assert git(repo, "worktree", "list", "--porcelain") == before


def test_submodule_base_uses_independent_clone(
    workspace: tuple[Path, Callable],
) -> None:
    """The requested base selects independent storage, even on another branch."""
    repo, cli = workspace
    oid = git(repo, "rev-parse", "HEAD")
    git(repo, "update-index", "--add", "--cacheinfo", "160000," + oid + ",component")
    git(repo, "commit", "-m", "gitlink fixture")
    git(repo, "branch", "with-submodule")
    git(repo, "checkout", "-b", "without-submodule", "HEAD~1")
    before = git(repo, "worktree", "list", "--porcelain")
    path = Path(
        cli("new", str(repo), "task", "--base", "with-submodule").stdout.strip()
    )
    assert (path / ".git").is_dir()
    assert git(path, "rev-parse", "HEAD") == git(repo, "rev-parse", "with-submodule")
    assert (
        Path(git(path, "rev-parse", "--path-format=absolute", "--git-common-dir"))
        == path / ".git"
    )
    assert any(tree["worktree"] == str(path) for tree in json.loads(cli("list").stdout))
    assert git(repo, "worktree", "list", "--porcelain") == before


def test_session_locks_checkout_until_command_finishes(
    workspace: tuple[Path, Callable],
) -> None:
    """The run command protects active work and releases its Git lock on exit."""
    repo, cli = workspace
    path = Path(cli("new", str(repo), "task", "--base", "main").stdout.strip())
    config = repo.parents[2] / "policy.json"
    with subprocess.Popen(
        [
            sys.executable,
            str(SCRIPT),
            "--config",
            str(config),
            "run",
            str(path),
            "--",
            sys.executable,
            str(Path(__file__).resolve().parents[1] / "fixtures/process.py"),
            "stdin-barrier",
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
    ) as process:
        try:
            assert process.stdout is not None
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                assert selector.select(5), "session did not become ready"
            assert process.stdout.readline() == b"ready\n"
            cli(
                "remove",
                str(path),
                "--apply",
                "--completed",
                "--retained-ref",
                "refs/heads/main",
                success=False,
            )
        finally:
            assert process.stdin is not None
            process.stdin.write(b"x")
            process.stdin.flush()
            process.wait()
    assert "locked" not in git(repo, "worktree", "list", "--porcelain")


def test_maintenance_optimizes_durable_storage_without_removing_tasks(
    workspace: tuple[Path, Callable],
) -> None:
    """Weekly optimization preserves dirty task work and committed references."""
    repo, cli = workspace
    path = Path(cli("new", str(repo), "task", "--base", "main").stdout.strip())
    (path / "tracked.txt").write_text("pending")
    head = git(repo, "rev-parse", "HEAD")
    cli("maintain", "--schedule", "weekly")
    assert path.exists()
    assert (path / "tracked.txt").read_text() == "pending"
    assert git(repo, "rev-parse", "HEAD") == head


def test_maintenance_works_without_remote_access(
    workspace: tuple[Path, Callable],
) -> None:
    """Local object maintenance succeeds before boot networking or login credentials."""
    repo, cli = workspace
    git(repo, "remote", "add", "origin", str(repo.parent / "unavailable-remote"))
    git(repo, "config", "maintenance.prefetch.enabled", "true")
    head = git(repo, "rev-parse", "HEAD")
    cli("maintain", "--schedule", "hourly")
    assert git(repo, "rev-parse", "HEAD") == head
    assert not git(repo, "for-each-ref", "refs/prefetch")


def test_clone_retention_must_survive_clone_deletion(
    workspace: tuple[Path, Callable],
) -> None:
    """A second ref inside an independent clone is not a durable backup."""
    repo, cli = workspace
    oid = git(repo, "rev-parse", "HEAD")
    git(repo, "update-index", "--add", "--cacheinfo", "160000," + oid + ",component")
    git(repo, "commit", "-m", "gitlink fixture")
    path = Path(cli("new", str(repo), "task", "--base", "main").stdout.strip())
    git(path, "config", "user.name", "Fixture")
    git(path, "config", "user.email", "fixture@example.invalid")
    git(path, "config", "commit.gpgsign", "false")
    git(path, "config", "core.hooksPath", str(repo.parent / "absent-hooks"))
    task_branch = git(path, "branch", "--show-current")
    git(path, "checkout", "-b", "saved-only-here")
    (path / "tracked.txt").write_text("unique clone commit")
    git(path, "commit", "-am", "unique")
    saved_commit = git(path, "rev-parse", "HEAD")
    git(path, "checkout", task_branch)
    cli(
        "remove",
        str(path),
        "--apply",
        "--completed",
        "--retained-ref",
        "refs/heads/main",
        success=False,
    )
    assert path.exists()
    assert git(path, "rev-parse", "saved-only-here") == saved_commit


def test_maintenance_deduplicates_storage_and_skips_app_clones(
    workspace: tuple[Path, Callable], monkeypatch: pytest.MonkeyPatch
) -> None:
    """Independent manual storage runs once and application storage is excluded."""
    repo, cli = workspace
    cli("new", str(repo), "one", "--base", "main")
    cli("new", str(repo), "two", "--base", "main")
    manual_clone = repo.parents[2] / "Worktrees/manual/local/independent"
    app_clone = repo.parents[2] / "Worktrees/codex/app-owned"
    git(repo, "clone", "--no-hardlinks", str(repo), str(manual_clone))
    git(repo, "clone", "--no-hardlinks", str(repo), str(app_clone))
    git(
        repo,
        "-c",
        "protocol.file.allow=always",
        "submodule",
        "add",
        str(app_clone),
        "component",
    )
    git(repo, "commit", "-am", "add component")
    legacy = repo.parents[2] / "Worktrees/manual/local/legacy"
    git(repo, "worktree", "add", "--detach", str(legacy), "main")
    git(
        legacy,
        "-c",
        "protocol.file.allow=always",
        "submodule",
        "update",
        "--init",
    )
    rows = json.loads(cli("doctor").stdout)
    for component in [repo / "component", legacy / "component"]:
        assert any(
            row["repository"] == str(component)
            and row["worktree"] == str(component)
            and not row["dirty"]
            for row in rows
        )
    log = repo.parent / "maintenance-log"
    proxy = repo.parent / "git-proxy"
    executable = shutil.which("git")
    assert executable is not None
    proxy.write_text(
        re.sub(
            r"__fixture_[0-9]+__",
            lambda match: {
                "__fixture_0__": str(sys.executable),
                "__fixture_1__": str(repr(str(log))),
                "__fixture_2__": str(repr(executable)),
                "__fixture_3__": str(repr(executable)),
            }[match[0]],
            (
                Path(__file__).with_name("fixtures") / "record_git_maintenance.py.in"
            ).read_text(encoding="utf-8"),
        )
    )
    proxy.chmod(0o700)
    monkeypatch.setenv("DEV_WORKTREE_GIT", str(proxy))
    cli("maintain", "--schedule", "weekly")
    assert sorted(log.read_text().splitlines()) == sorted([
        str(repo),
        str(manual_clone),
        str(repo / "component"),
        str(legacy / "component"),
    ])


@pytest.mark.parametrize("schedule", ["hourly", "daily", "weekly"])
def test_orphan_linked_task_is_reported_without_blocking_healthy_maintenance(
    workspace: tuple[Path, Callable], monkeypatch: pytest.MonkeyPatch, schedule: str
) -> None:
    """Missing task metadata preserves task bytes and records while real Git runs."""
    repo, cli = workspace
    path = Path(cli("new", str(repo), "orphan", "--base", "main").stdout.strip())
    metadata = Path(git(path, "rev-parse", "--absolute-git-dir"))
    (path / "tracked.txt").write_text("unsaved task work\n")
    (path / "untracked.txt").write_text("unregistered task data\n")
    # Simulate an external loss of administrative state in this disposable fixture.
    shutil.rmtree(metadata)
    records = repo.parents[2] / "state/records"
    saved = {
        "files": {p.name: p.read_bytes() for p in path.iterdir() if p.is_file()},
        "records": {p.name: p.read_bytes() for p in records.glob("*.json")},
        "index": (repo / ".git/index").read_bytes(),
        "trees": git(repo, "worktree", "list", "--porcelain"),
        "head": git(repo, "rev-parse", "HEAD"),
    }
    log = repo.parent / "orphan-maintenance-log"
    proxy = repo.parent / "orphan-git-proxy"
    executable = shutil.which("git")
    assert executable is not None
    substitutions = {
        "__fixture_0__": str(sys.executable),
        "__fixture_1__": repr(str(log)),
        "__fixture_2__": repr(executable),
        "__fixture_3__": repr(executable),
    }
    proxy.write_text(
        re.sub(
            r"__fixture_[0-9]+__",
            lambda match: substitutions[match[0]],
            (
                Path(__file__).with_name("fixtures") / "record_git_maintenance.py.in"
            ).read_text(),
        )
    )
    proxy.chmod(0o700)
    monkeypatch.setenv("DEV_WORKTREE_GIT", str(proxy))
    rows = json.loads(cli("doctor").stdout)
    unavailable = next(row for row in rows if row["worktree"] == str(path))
    assert unavailable["available"] is False
    assert unavailable["exists"] is True
    assert unavailable["owner"] == "manual"
    assert "preserved" in unavailable["diagnostic"]
    assert any(row["worktree"] == str(repo) for row in rows)
    result = cli("maintain", "--schedule", schedule)
    assert "Skipping unavailable discovered worktree" in result.stderr
    assert log.read_text().splitlines() == [str(repo)]
    assert {p.name: p.read_bytes() for p in path.iterdir() if p.is_file()} == saved[
        "files"
    ]
    assert {p.name: p.read_bytes() for p in records.glob("*.json")} == saved["records"]
    assert (repo / ".git/index").read_bytes() == saved["index"]
    assert git(repo, "worktree", "list", "--porcelain") == saved["trees"]
    assert git(repo, "rev-parse", "HEAD") == saved["head"]


def test_unknown_orphan_diagnostic_does_not_publish_git_credential_stderr(
    workspace: tuple[Path, Callable],
) -> None:
    """A real Git failure is reported without exposing its credential-bearing path."""
    repo, cli = workspace
    path = repo.parents[2] / "Worktrees/manual/local/unknown-orphan"
    path.mkdir(parents=True)
    metadata = path.parent / ".unavailable-admin"
    git(
        repo,
        "init",
        "--initial-branch=main",
        "--separate-git-dir=" + str(metadata),
        str(path),
    )
    git(path, "config", "core.repositoryformatversion", "1")
    # Git's format parser reports the rejected value verbatim. Use real Git,
    # rather than relying on version-dependent missing-gitdir diagnostics.
    git(
        path,
        "config",
        "extensions.objectFormat",
        "https://fixture-user:fixture-token@example.invalid",
    )
    pointer = (path / ".git").read_text()
    configuration = (metadata / "config").read_bytes()
    (path / "saved.txt").write_text("preserve unknown work\n")
    failure = subprocess.run(
        ["git", "-C", str(path), "ls-files", "--stage"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert failure.returncode != 0
    assert "fixture-token" in failure.stderr
    result = cli("doctor")
    row = next(row for row in json.loads(result.stdout) if row["worktree"] == str(path))
    assert row["available"] is False
    assert row["owner"] == "unknown"
    maintenance = cli("maintain", "--schedule", "hourly")
    for output in [
        result.stdout,
        result.stderr,
        maintenance.stdout,
        maintenance.stderr,
    ]:
        assert "fixture-token" not in output
        assert "fixture-user" not in output
    assert (path / ".git").read_text() == pointer
    assert (metadata / "config").read_bytes() == configuration
    assert (path / "saved.txt").read_text() == "preserve unknown work\n"


@pytest.mark.parametrize("kind", ["missing", "invalid-linked"])
def test_explicit_unavailable_repository_is_not_silently_ignored(
    workspace: tuple[Path, Callable], kind: str
) -> None:
    """Configuration remains authoritative even for an automatic linked candidate."""
    repo, cli = workspace
    base = repo.parents[2]
    bad = base / "Worktrees/manual/local/explicit-unavailable"
    if kind == "invalid-linked":
        bad.mkdir(parents=True)
        (bad / ".git").write_text(
            "gitdir: https://fixture-user:fixture-token@example.invalid/missing\n"
        )
    config = base / "policy.json"
    policy = json.loads(config.read_text())
    policy["repositories"].append(str(bad))
    config.write_text(json.dumps(policy))
    index = (repo / ".git/index").read_bytes()
    for command in [["doctor"], ["maintain", "--schedule", "weekly"]]:
        result = cli(*command, success=False)
        assert "fixture-token" not in result.stderr
        assert "fixture-user" not in result.stderr
    assert (repo / ".git/index").read_bytes() == index


def test_selected_repository_maintenance_failure_still_fails(
    workspace: tuple[Path, Callable],
) -> None:
    """A real selected-store write failure cannot become an ignored discovery issue."""
    repo, cli = workspace
    git(repo, "config", "maintenance.commit-graph.enabled", "true")
    blocked = repo / ".git/objects/info/commit-graphs"
    blocked.write_text("fixture blocks the graph directory\n")
    result = cli("maintain", "--schedule", "weekly", success=False)
    assert "Maintenance failed for " + str(repo) in result.stderr
    assert blocked.read_text() == "fixture blocks the graph directory\n"


def test_linked_task_with_valid_metadata_and_corrupt_index_fails_closed(
    workspace: tuple[Path, Callable],
) -> None:
    """An available object store cannot hide a distinct linked-index corruption."""
    repo, cli = workspace
    path = Path(cli("new", str(repo), "corrupt-index", "--base", "main").stdout.strip())
    metadata = Path(git(path, "rev-parse", "--absolute-git-dir"))
    index = metadata / "index"
    index.write_bytes(b"not a Git index")
    assert git(path, "rev-parse", "--git-common-dir")
    (path / "untracked.txt").write_text("preserve task data\n")
    records = repo.parents[2] / "state/records"
    saved = {p.name: p.read_bytes() for p in records.glob("*.json")}
    canonical_index = (repo / ".git/index").read_bytes()
    for command in [["doctor"], ["maintain", "--schedule", "hourly"]]:
        result = cli(*command, success=False)
        assert "Git operation failed" in result.stderr
        assert "Skipping unavailable" not in result.stderr
    assert index.read_bytes() == b"not a Git index"
    assert (repo / ".git/index").read_bytes() == canonical_index
    assert (path / "untracked.txt").read_text() == "preserve task data\n"
    assert {p.name: p.read_bytes() for p in records.glob("*.json")} == saved
