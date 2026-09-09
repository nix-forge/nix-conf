"""Reject private email before Git records or publishes it; preserve local hooks."""

# Diagnostics are fixed, redacted strings used directly by this CLI.
# ruff: file-ignore[raise-vanilla-args, raw-string-in-exception]

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Git plumbing and existing hooks are intentional subprocesses.
import sys
from pathlib import Path


class PrivacyError(Exception):
    """A privacy check could not safely permit the operation."""


def run(command: list[str], data: bytes | None = None) -> bytes:
    """Capture diagnostics because Git errors can contain private identities.

    Returns:
        Command output after successful completion.

    Raises:
        PrivacyError: The command failed; its diagnostics remain private.

    """
    result = subprocess.run(
        command, input=data, capture_output=True, check=False, timeout=120
    )
    if result.returncode:
        raise PrivacyError("Privacy check failed; no data was published.")
    return result.stdout


class Guard:
    """Check immutable Git objects using a protected, machine-local policy."""

    def __init__(self, git: str, gh: str) -> None:
        """Load addresses from the owner-only runtime policy.

        Raises:
            PrivacyError: The runtime policy is missing or unsafe.

        """
        self.git = git
        self.gh = gh
        policy_path = (
            run([
                git,
                "config",
                "--global",
                "--includes",
                "--path",
                "--get",
                "privacy.policyFile",
            ])
            .decode()
            .strip()
        )
        policy_file = Path(policy_path)
        if policy_file.stat().st_mode & 0o077:
            raise PrivacyError(
                "Private email policy must be readable only by its owner."
            )
        policy = json.loads(policy_file.read_text(encoding="utf-8"))
        addresses = policy["blockedEmails"]
        if not addresses or not all(isinstance(a, str) and "@" in a for a in addresses):
            raise PrivacyError("Private email policy is missing or invalid.")
        self.patterns = tuple(
            variant
            for address in addresses
            for variant in (
                address.lower().encode(),
                address.lower().replace("@", "\\@").encode(),
                address.lower().replace("@", "%40").encode(),
                address.lower().replace("@", "&#64;").encode(),
                address.lower().replace("@", "&#x40;").encode(),
            )
        )
        self.overlap = max(map(len, self.patterns)) - 1
        self.private_repositories = policy.get("privateContentRepositories", [])

    def inspect(self, data: bytes) -> None:
        """Check bytes without disclosing the matching value.

        Raises:
            PrivacyError: A blocked address occurs in the data.

        """
        if any(pattern in data.lower() for pattern in self.patterns):
            raise PrivacyError(
                "Blocked private email in Git data. Use your public noreply identity "
                "and remove private addresses from published content."
            )

    def private_content(self, destination: str | None = None) -> bool:
        """Allow a named private repository only after verifying GitHub visibility.

        Returns:
            Whether every destination matches an explicitly allowed private repository.

        """
        if not self.private_repositories:
            return False
        if destination is None:
            names = run([self.git, "remote"]).decode().splitlines()
            urls = [
                run([self.git, "remote", "get-url", name]).decode().strip()
                for name in names
            ]
        else:
            urls = [destination]
        if not urls:
            return False
        for url in urls:
            match = re.fullmatch(
                r"(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)"
                r"([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?",
                url,
            )
            if not match or match[1] not in self.private_repositories:
                return False
            repository = json.loads(
                run([self.gh, "api", "--hostname", "github.com", "repos/" + match[1]])
            )
            if repository.get("private") is not True:
                return False
        return True

    def objects(self, object_ids: list[bytes], *, allow_content: bool = False) -> None:  # ruff: ignore[complex-structure] - One sequential parser owns the batch stream and cleanup.
        """Stream objects, including large blobs, without printing their contents.

        Raises:
            PrivacyError: An object is unavailable, malformed, or contains private email.

        """
        process = subprocess.Popen(
            [self.git, "cat-file", "--batch"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        assert process.stdin is not None  # ruff: ignore[assert] - Guaranteed by stdin=PIPE; narrows its type.
        assert process.stdout is not None  # ruff: ignore[assert] - Guaranteed by stdout=PIPE; narrows its type.
        try:
            for oid in dict.fromkeys(object_ids):
                if not re.fullmatch(rb"[0-9a-f]{40}|[0-9a-f]{64}", oid):
                    raise PrivacyError("Invalid Git object ID.")
                process.stdin.write(oid + b"\n")
                process.stdin.flush()
                header = process.stdout.readline().split()
                if len(header) != 3:  # ruff: ignore[magic-value-comparison] - cat-file returns object ID, type, and size.
                    raise PrivacyError("Cannot inspect an outgoing Git object.")
                _, kind, size = header
                remaining = int(size)
                tail = b""
                while remaining:
                    chunk = process.stdout.read(min(remaining, 1024 * 1024))
                    if not chunk:
                        raise PrivacyError("Incomplete Git object.")
                    if not (allow_content and kind == b"blob"):
                        self.inspect(tail + chunk)
                        tail = (tail + chunk)[-self.overlap :]
                    remaining -= len(chunk)
                if process.stdout.read(1) != b"\n":
                    raise PrivacyError("Invalid Git object boundary.")
            process.stdin.close()
            if process.wait():
                raise PrivacyError("Git object inspection failed.")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()
            if not process.stdin.closed:
                process.stdin.close()

    def before_commit(self) -> None:
        """Inspect the effective identities and complete staged snapshot.

        Raises:
            PrivacyError: The index has unresolved conflicts or contains private email.

        """
        for identity in ("GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"):
            self.inspect(run([self.git, "var", identity]))
        staged = run([self.git, "ls-files", "--stage", "-z"])
        objects = []
        for record in staged.split(b"\0"):
            if not record:
                continue
            metadata, path = record.split(b"\t", 1)
            self.inspect(path)
            mode, oid, stage = metadata.split()
            if stage != b"0":
                raise PrivacyError("Resolve the unmerged index before committing.")
            if mode != b"160000":
                objects.append(oid)
        self.objects(objects, allow_content=self.private_content())

    def before_push(self, destination: str, updates: bytes) -> None:
        """Inspect objects being newly published to this exact destination."""
        tips = []
        for line in updates.splitlines():
            local_ref, local_oid, remote_ref, _ = line.split()
            self.inspect(local_ref + b" " + remote_ref)
            if local_oid.strip(b"0"):
                tips.append(local_oid)
        if not tips:
            return  # Ref deletion uploads no commit or content.
        # Only exclude current branch/tag objects actually advertised by this
        # destination. Stale tracking refs or GitHub PR refs must not hide leaks.
        advertised = run([
            self.git,
            "ls-remote",
            "--refs",
            "--",
            destination,
            "refs/heads/*",
            "refs/tags/*",
        ])
        bases = list(dict.fromkeys(line.split()[0] for line in advertised.splitlines()))
        known = run(
            [self.git, "cat-file", "--batch-check=%(objectname) %(objecttype)"],
            b"\n".join(bases) + (b"\n" if bases else b""),
        )
        exclusions = [
            b"^" + line.split()[0]
            for line in known.splitlines()
            if line.split()[-1] in {b"commit", b"tag"}
        ]
        objects = run(
            [self.git, "rev-list", "--objects", "--no-object-names", "--stdin"],
            b"\n".join(tips + exclusions) + b"\n",
        ).splitlines()
        self.objects(tips + objects, allow_content=self.private_content(destination))


def main() -> int:  # ruff: ignore[complex-structure] - Dispatch covers Git initialization and forwarding repository hooks.
    """Run the guard and preserve the repository's hook behavior.

    Returns:
        Zero on success, or the repository hook's failure status.

    Raises:
        PrivacyError: A hook loop or unsafe operation is detected.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--git", default="git")
    parser.add_argument("--gh", default="gh")
    parser.add_argument("hook")
    parser.add_argument("arguments", nargs="*")
    args = parser.parse_args()
    data = sys.stdin.buffer.read() if args.hook == "pre-push" else None
    active_hooks = os.environ.get("GIT_PRIVACY_ACTIVE_HOOKS", "").split(":")
    if args.hook in active_hooks:
        raise PrivacyError("Recursive Git hook configuration; check your local hooks.")
    try:
        common = Path(run([args.git, "rev-parse", "--git-common-dir"]).decode().strip())
    except PrivacyError:
        # git init invokes reference-transaction before HEAD exists, when
        # rev-parse cannot yet recognize the repository. No commit is published.
        if args.hook == "reference-transaction":
            return 0
        raise
    local_hook = common / "hooks" / args.hook

    def delegate() -> int:
        if local_hook.is_file() and os.access(local_hook, os.X_OK):
            environment = dict(os.environ)
            environment["GIT_PRIVACY_ACTIVE_HOOKS"] = ":".join([
                *active_hooks,
                args.hook,
            ])
            return subprocess.run(
                [str(local_hook.resolve()), *args.arguments],
                input=data,
                env=environment,
                check=False,
            ).returncode
        return 0

    # Check the final index and message after repository hooks modify them.
    # Before a push, reject private data before running other push integrations.
    if args.hook != "pre-push":
        status = delegate()
        if status:
            return status
    if args.hook in {"pre-commit", "pre-merge-commit", "commit-msg", "pre-push"}:
        guard = Guard(args.git, args.gh)
        if args.hook in {"pre-commit", "pre-merge-commit"}:
            guard.before_commit()
        elif args.hook == "commit-msg":
            guard.before_commit()
            guard.inspect(Path(args.arguments[0]).read_bytes())
        else:
            guard.before_push(args.arguments[1], data or b"")
    return delegate() if args.hook == "pre-push" else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (
        PrivacyError,
        OSError,
        ValueError,
        KeyError,
        IndexError,
        subprocess.TimeoutExpired,
    ) as error:
        message = (
            str(error)
            if isinstance(error, PrivacyError)
            else "Private email protection failed closed."
        )
        sys.stderr.write(message + "\n")
        sys.exit(1)
