"""Manage explicitly owned task checkouts and maintain durable Git repositories."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import TYPE_CHECKING
from urllib.parse import urlsplit

if TYPE_CHECKING:
    from collections.abc import Generator


class RefusedError(RuntimeError):
    """The operation cannot preserve the checkout's ownership or saved work."""


def git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    """Run Git directly without shell expansion or inherited repository overrides.

    Returns:
        The captured Git command result.

    """
    environment = {
        key: value for key, value in os.environ.items() if not key.startswith("GIT_")
    }
    environment["GIT_TERMINAL_PROMPT"] = "0"
    environment["GIT_OPTIONAL_LOCKS"] = "0"
    return subprocess.run(
        [os.environ.get("DEV_WORKTREE_GIT", "git"), "-C", str(repo), *args],
        env=environment,
        capture_output=True,
        text=True,
        check=check,
    )


def common(repo: Path) -> Path:
    """Resolve the repository's shared object storage independently of checkout type.

    Returns:
        The absolute common Git directory.

    """
    return Path(
        git(
            repo, "rev-parse", "--path-format=absolute", "--git-common-dir"
        ).stdout.strip()
    ).resolve()


def scan(root: Path, depth: int = 4) -> list[Path]:
    """Find checkouts without descending into source trees or following symlinks.

    Returns:
        Existing checkout roots.

    """
    if not root.is_dir() or root.is_symlink():
        return []
    if (root / ".git").exists():
        return [root]
    if depth == 0:
        return []
    return [
        repo
        for child in sorted(root.iterdir())
        if child.is_dir() and not child.is_symlink() and not child.name.startswith(".")
        for repo in scan(child, depth - 1)
    ]


def worktrees(repo: Path) -> list[dict[str, str]]:
    """Read Git's stable NUL-delimited worktree records.

    Returns:
        Git worktree records.

    """
    result: list[dict[str, str]] = []
    current: dict[str, str] = {}
    for field in git(repo, "worktree", "list", "--porcelain", "-z").stdout.split("\0"):
        if not field:
            if current:
                result.append(current)
                current = {}
        else:
            key, _, value = field.partition(" ")
            current[key] = value
    # Git reports an absorbed submodule's main worktree at its metadata
    # directory. Inventory should show the checkout selected by core.worktree.
    if result and result[0].get("worktree") == str(common(repo)):
        result[0]["worktree"] = git(repo, "rev-parse", "--show-toplevel").stdout.strip()
    return result


def submodules(repo: Path) -> list[Path]:
    """Include initialized submodules without executing shell callbacks.

    Returns:
        Initialized submodule checkouts.

    """
    result: list[Path] = []
    for entry in git(repo, "ls-files", "--stage", "-z").stdout.split("\0"):
        if entry.startswith("160000 "):
            path = repo / entry.partition("\t")[2]
            if (path / ".git").exists():
                result.extend([path, *submodules(path)])
    return result


def unavailable_git_metadata(repo: Path) -> bool:
    """Distinguish missing administration from a failed index or discovery command.

    Returns:
        Whether Git cannot resolve this checkout's administrative object store.

    """
    try:
        common(repo)
    except subprocess.CalledProcessError:
        return True
    return False


def durable_repos(configuration: dict) -> tuple[list[Path], list[Path]]:
    """Discover durable stores and report unavailable automatic linked tasks.

    Returns:
        Deduplicated durable checkouts and preserved unavailable linked tasks.

    Raises:
        RefusedError: An explicitly configured repository has no Git metadata.
        CalledProcessError: Git failed for a configured or administratively
            available repository.

    """
    manual = (Path(configuration["worktreeRoot"]) / "manual").resolve()
    configured = [Path(path) for path in configuration.get("repositories", [])]
    for repo in configured:
        if not (repo / ".git").exists():
            raise RefusedError("Configured repository is unavailable: " + str(repo))
    explicit = {repo.resolve() for repo in configured}
    roots = scan(Path(configuration["developerRoot"])) + scan(manual, depth=8)
    candidates = configured.copy()
    unavailable: list[Path] = []
    for repo in roots:
        # Legacy superproject worktrees can have independent submodule storage
        # even though their parent checkout shares its canonical object store.
        try:
            candidates.extend(submodules(repo))
        except subprocess.CalledProcessError:
            # An automatic task discovery is not authority to repair or remove
            # its unavailable administrative directory. Keep it in inventory,
            # while healthy canonical stores remain eligible for maintenance.
            if (
                (repo / ".git").is_file()
                and repo.resolve().is_relative_to(manual)
                and repo.resolve() not in explicit
                and unavailable_git_metadata(repo)
            ):
                unavailable.append(repo.resolve())
                continue
            raise
        if (repo / ".git").is_dir():
            candidates.append(repo)
    unique: dict[Path, Path] = {}
    for repo in candidates:
        if (repo / ".git").exists():
            unique.setdefault(common(repo), repo.resolve())
    return list(unique.values()), unavailable


def write_json(path: Path, value: dict) -> None:
    """Replace a private registry record atomically."""
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=".record-")
    try:
        with os.fdopen(descriptor, "w") as output:
            json.dump(value, output, indent=2)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        Path(temporary).replace(path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def key(path: Path) -> str:
    """Keep registry filenames independent of private repository names.

    Returns:
        The hashed path identity.

    """
    return hashlib.sha256(os.fsencode(path)).hexdigest()


@contextmanager
def lease(state: Path, name: str) -> Generator[None]:
    """Serialize mutations and prevent managed runs from racing deletion.

    Raises:
        RefusedError: The operation would violate ownership or preservation rules.

    """
    locks = state / "locks"
    locks.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (locks / name).open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RefusedError(
                "Another managed operation or session is using this checkout"
            ) from error
        yield


def identity(repo: Path) -> Path:
    """Derive a collision-resistant identity without exposing remote credentials.

    Returns:
        The forge identity or a local fallback identity.

    """
    remote = git(
        repo, "config", "--get", "remote.origin.url", check=False
    ).stdout.strip()
    if "://" not in remote and re.match(r"[^/]+@[^:]+:", remote):
        remote = "ssh://" + remote.replace(":", "/", 1)
    parsed = urlsplit(remote)
    parts = [
        parsed.hostname or "",
        *parsed.path.removesuffix(".git").strip("/").split("/"),
    ]
    if (
        parsed.scheme in {"https", "http", "ssh", "git"}
        and len(parts) >= len(("forge", "owner", "repo"))
        and all(re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9._-]*", part) for part in parts)
    ):
        return Path(*parts)
    return Path("local", repo.name + "-" + key(common(repo))[:8])


def retained(repo: Path, commit: str, requested: str, task_branch: str) -> bool:
    """Check retention in storage that survives checkout deletion.

    Returns:
        Whether a canonical ref retains the task commit.

    Raises:
        RefusedError: A requested ref is unnamed or is the task's own branch.

    """
    references = git(
        repo, "for-each-ref", "--format=%(refname)", "refs/remotes/"
    ).stdout.splitlines()
    if requested:
        if not requested.startswith("refs/") or requested == task_branch:
            raise RefusedError(
                "Retained ref must be a named ref other than this task's branch"
            )
        references = [requested]
    return any(
        git(repo, "merge-base", "--is-ancestor", commit, ref, check=False).returncode
        == 0
        for ref in references
    )


class Manager:
    """Own manual checkout records while leaving app-managed directories untouched."""

    def __init__(self, configuration: dict) -> None:
        """Bind roots and private state from the declarative policy."""
        self.configuration = configuration
        self.root = Path(configuration["worktreeRoot"]).resolve()
        self.manual = self.root / "manual"
        self.state = Path(configuration["stateDirectory"]).resolve()

    def record_file(self, path: Path) -> Path:
        """Return the external record for this absolute path.

        Returns:
            The external ownership record path.

        """
        return self.state / "records" / (key(path) + ".json")

    def records(self) -> list[dict]:
        """Read only complete atomic records.

        Returns:
            Saved ownership records.

        """
        return [
            json.loads(path.read_text())
            for path in sorted((self.state / "records").glob("*.json"))
        ]

    def owned(self, path: Path) -> dict:
        """Reject unregistered, moved, replaced, or application-owned directories.

        Returns:
            The verified manual ownership record.

        Raises:
            RefusedError: The operation would violate ownership or preservation rules.

        """
        record = self.record_file(path)
        if not path.is_relative_to(self.manual) or not record.exists():
            raise RefusedError("Checkout is not registered as manually owned")
        value = json.loads(record.read_text())
        if value["path"] != str(path) or value["commonDirectory"] != str(common(path)):
            raise RefusedError("Checkout no longer matches its ownership record")
        return value

    def save(self, path: Path, repo: Path, task: str) -> None:
        """Register a checkout without adding files to its working tree."""
        write_json(
            self.record_file(path),
            {
                "path": str(path),
                "repository": str(repo),
                "commonDirectory": str(common(path)),
                "task": task,
                "owner": "manual",
                "createdHead": git(path, "rev-parse", "HEAD").stdout.strip(),
            },
        )

    def new(self, repo: Path, task: str, base: str) -> Path:
        """Create a unique checkout from an explicit committed base.

        Returns:
            The created checkout path.

        Raises:
            RefusedError: The operation would violate ownership or preservation rules.

        """
        if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}", task):
            raise RefusedError(
                "Task must be a short name containing letters, numbers, underscores, or hyphens"
            )
        if not (repo / ".git").is_dir():
            raise RefusedError(
                "Create tasks from a main clone; submodule tasks need their own reviewed setup"
            )
        commit = git(repo, "rev-parse", "--verify", base + "^{commit}").stdout.strip()
        needs_clone = any(
            entry.startswith("160000 ")
            for entry in git(repo, "ls-tree", "-r", "-z", commit).stdout.split("\0")
        )
        name = task + "-" + uuid.uuid4().hex[:8]
        path = self.manual / identity(repo) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if needs_clone:
            git(
                repo,
                "clone",
                "--no-hardlinks",
                "--no-checkout",
                "--",
                str(repo),
                str(path),
            )
            git(path, "checkout", "-b", "codex/" + name, commit)
            # Keep upstream submodule URL resolution consistent with the source.
            remote = git(
                repo, "config", "--get", "remote.origin.url", check=False
            ).stdout.strip()
            if remote:
                git(path, "remote", "set-url", "origin", remote)
        else:
            git(repo, "worktree", "add", "-b", "codex/" + name, str(path), commit)
        self.save(path, repo, task)
        return path

    def inspect(self) -> list[dict]:
        """Inventory Git state and placement without mutating any repository.

        Returns:
            Live worktree and placement information.

        """
        repos, unavailable = durable_repos(self.configuration)
        for record in self.records():
            repo = Path(record["repository"])
            if (repo / ".git").exists() and common(repo) not in {
                common(item) for item in repos
            }:
                repos.append(repo)
        output: list[dict] = [
            {
                "repository": str(path),
                "worktree": str(path),
                "exists": path.exists(),
                "owner": "manual" if self.record_file(path).exists() else "unknown",
                "available": False,
                "diagnostic": "Git discovery unavailable; checkout preserved",
            }
            for path in unavailable
        ]
        for repo in repos:
            for tree in worktrees(repo):
                path = Path(tree["worktree"])
                row = {
                    "repository": str(repo),
                    **tree,
                    "exists": path.exists(),
                    "owner": "unknown",
                }
                if self.record_file(path).exists() or any(
                    parent.is_relative_to(self.manual)
                    and self.record_file(parent).exists()
                    for parent in path.parents
                ):
                    row["owner"] = "manual"
                elif path.resolve() == repo:
                    row["owner"] = "canonical"
                if path.exists():
                    row["dirty"] = bool(
                        git(
                            path,
                            "status",
                            "--porcelain",
                            "--untracked-files=all",
                            "--ignore-submodules=none",
                        ).stdout
                    )
                output.append(row)
        return output

    def remove(
        self,
        path: Path,
        retained_ref: str,
        apply: bool,
        completed: bool,
        discard_ignored: bool,
    ) -> None:
        """Remove only completed, clean manual work with a verified retained commit.

        Raises:
            RefusedError: The operation would violate ownership or preservation rules.

        """
        record = self.owned(path)
        if (path / ".git").is_dir():
            raise RefusedError(
                "Independent clones contain their own branches, stashes, and object storage; use reviewed archival"
            )
        tree = next(
            item for item in worktrees(path) if Path(item["worktree"]).resolve() == path
        )
        if "locked" in tree:
            raise RefusedError("Worktree is locked; finish its session before removal")
        if git(
            path,
            "status",
            "--porcelain",
            "--untracked-files=all",
            "--ignore-submodules=none",
        ).stdout:
            raise RefusedError(
                "Checkout contains tracked, untracked, or submodule changes"
            )
        if (
            git(
                path, "ls-files", "--others", "--ignored", "--exclude-standard", "-z"
            ).stdout
            and not discard_ignored
        ):
            raise RefusedError(
                "Checkout contains ignored files; preserve them or explicitly pass --discard-ignored"
            )
        if not retained(
            Path(record["repository"]),
            git(path, "rev-parse", "HEAD").stdout.strip(),
            retained_ref,
            tree.get("branch", ""),
        ):
            raise RefusedError(
                "HEAD is not retained by a ref in the canonical repository"
            )
        if not apply:
            print("Would remove " + str(path))
            return
        if not completed:
            raise RefusedError(
                "Pass --completed after closing all editors and agent sessions for this checkout"
            )
        git(path, "worktree", "remove", str(path))
        self.record_file(path).unlink()

    def move(self, path: Path, apply: bool, completed: bool = False) -> Path:
        """Adopt and relocate an ordinary linked checkout from Developer using Git.

        Returns:
            The proposed or applied destination path.

        Raises:
            RefusedError: The operation would violate ownership or preservation rules.

        """
        developer = Path(self.configuration["developerRoot"]).resolve()
        if not path.is_relative_to(developer) or (path / ".git").is_dir():
            raise RefusedError(
                "Migration accepts only linked task checkouts under Developer"
            )
        trees = worktrees(path)
        tree = next(item for item in trees if Path(item["worktree"]).resolve() == path)
        if "locked" in tree or submodules(path):
            raise RefusedError(
                "Locked worktrees and initialized submodules require separate migration"
            )
        repo = Path(trees[0]["worktree"]).resolve()
        if repo == path:
            raise RefusedError(
                "Submodule main checkouts cannot be moved as task worktrees"
            )
        destination = (
            self.manual / identity(repo) / (path.name + "-" + uuid.uuid4().hex[:8])
        )
        if not apply:
            print(str(path) + " -> " + str(destination))
            return destination
        if not completed:
            raise RefusedError(
                "Pass --completed after closing editors and agent sessions before moving"
            )
        destination.parent.mkdir(parents=True, exist_ok=True)
        git(repo, "worktree", "move", str(path), str(destination))
        self.save(destination, repo, path.name)
        return destination

    def maintain(self, schedule: str) -> int:
        """Run incremental maintenance once per durable object store, without checkout cleanup.

        Returns:
            One if any repository failed, otherwise zero.

        """
        failed = 0
        repos, unavailable = durable_repos(self.configuration)
        for path in unavailable:
            # Do not publish Git's stderr: it can contain credential-bearing URLs.
            print(
                "Skipping unavailable discovered worktree: " + str(path),
                file=sys.stderr,
            )
        for repo in repos:
            result = git(
                repo,
                "-c",
                "maintenance.strategy=incremental",
                # Scheduled object maintenance must work before networking or
                # credential agents are ready. Explicit fetches own remote I/O.
                "-c",
                "maintenance.prefetch.enabled=false",
                "maintenance",
                "run",
                "--schedule=" + schedule,
                check=False,
            )
            if result.returncode:
                print("Maintenance failed for " + str(repo), file=sys.stderr)
                failed = 1
        return failed


def parse_args() -> argparse.Namespace:
    """Parse preview-first operations and terminal session arguments.

    Returns:
        The selected command and its arguments.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config",
        type=Path,
        default=Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
        / "dev-worktree/config.json",
    )
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("new")
    create.add_argument("repository", type=Path)
    create.add_argument("task")
    create.add_argument("--base", required=True)
    commands.add_parser("list")
    commands.add_parser("doctor")
    move = commands.add_parser("move")
    move.add_argument("path", type=Path)
    move.add_argument("--apply", action="store_true")
    move.add_argument("--completed", action="store_true")
    remove = commands.add_parser("remove")
    remove.add_argument("path", type=Path)
    remove.add_argument("--retained-ref", default="")
    remove.add_argument("--apply", action="store_true")
    remove.add_argument("--completed", action="store_true")
    remove.add_argument("--discard-ignored", action="store_true")
    run = commands.add_parser("run")
    run.add_argument("path", type=Path)
    run.add_argument("arguments", nargs=argparse.REMAINDER)
    maintain = commands.add_parser("maintain")
    maintain.add_argument(
        "--schedule", choices=["hourly", "daily", "weekly"], required=True
    )
    return parser.parse_args()


def main() -> int:
    """Execute the selected operation.

    Returns:
        The command exit status.

    Raises:
        RefusedError: Ownership or preservation checks reject the operation.

    """
    args = parse_args()
    manager = Manager(json.loads(args.config.read_text()))
    if args.command in {"list", "doctor"}:
        print(json.dumps(manager.inspect(), indent=2))
        return 0
    if args.command == "maintain":
        with lease(manager.state, "maintenance"):
            return manager.maintain(args.schedule)
    if args.command == "run":
        path = args.path.resolve()
        manager.owned(path)
        arguments = (
            args.arguments[1:] if args.arguments[:1] == ["--"] else args.arguments
        )
        if not arguments:
            raise RefusedError("Supply a command after --")
        with lease(manager.state, key(path)):
            linked = not (path / ".git").is_dir()
            if linked:
                git(
                    path,
                    "worktree",
                    "lock",
                    "--reason",
                    "dev-worktree managed session",
                    str(path),
                )
            try:
                return subprocess.run(arguments, cwd=path, check=False).returncode
            finally:
                if linked:
                    git(path, "worktree", "unlock", str(path))
    with lease(manager.state, "mutation"):
        if args.command == "new":
            print(manager.new(args.repository.resolve(), args.task, args.base))
        else:
            path = args.path.resolve()
            with lease(manager.state, key(path)):
                if args.command == "move":
                    manager.move(path, args.apply, args.completed)
                else:
                    manager.remove(
                        path,
                        args.retained_ref,
                        args.apply,
                        args.completed,
                        args.discard_ignored,
                    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RefusedError, OSError, ValueError, subprocess.CalledProcessError) as error:
        # Git's raw stderr may contain credential-bearing remote URLs.
        print(
            "dev-worktree: "
            + (
                "Git operation failed"
                if isinstance(error, subprocess.CalledProcessError)
                else str(error)
            ),
            file=sys.stderr,
        )
        sys.exit(1)
