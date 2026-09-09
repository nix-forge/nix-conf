"""Exercise privacy protection through Git in disposable local repositories."""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = (
    Path(__file__).resolve().parents[2] / "modules/home/dev/scripts/git-privacy-hook.py"
)
PRIVATE = "private@example.invalid"
PUBLIC = "123+tester@users.noreply.github.com"
ZERO = "0" * 40


class HookTests(unittest.TestCase):
    """Check commit and publication behavior without contacting a real server."""

    def setUp(self) -> None:
        """Create an isolated identity, policy, hooks directory, and destination."""
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.remote = self.root / "remote.git"
        self.policy = self.root / "policy.json"
        self.policy.write_text(
            json.dumps({
                "blockedEmails": [PRIVATE, "fallback@example.invalid"],
                "privateContentRepositories": ["test-owner/private-project"],
            }),
            encoding="utf-8",
        )
        self.policy.chmod(0o600)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        self.env.update({
            "HOME": str(self.root),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": str(self.root / "gitconfig"),
            "GIT_TERMINAL_PROMPT": "0",
        })
        self.git("init", "--initial-branch=main")
        self.git("init", "--bare", str(self.remote))
        self.git("config", "--global", "user.name", "Fixture")
        self.git("config", "--global", "user.email", PUBLIC)
        self.git("config", "--global", "user.useConfigOnly", "true")
        self.git("config", "--global", "commit.gpgSign", "false")
        settings = self.root / "included-settings"
        self.git(
            "config", "--file", str(settings), "privacy.policyFile", str(self.policy)
        )
        self.git("config", "--global", "include.path", str(settings))
        self.fake_gh = self.root / "gh"
        self.fake_gh.write_text(
            "#!/bin/sh\nprintf '{\"private\":true}\\n'\n", encoding="utf-8"
        )
        self.fake_gh.chmod(0o700)
        self.hooks = self.root / "hooks"
        self.hooks.mkdir()
        for hook in [
            "pre-commit",
            "commit-msg",
            "pre-push",
            "post-commit",
            "reference-transaction",
        ]:
            entry = self.hooks / hook
            entry.write_text(
                "#!/bin/sh\nexec "
                + shlex.join([
                    sys.executable,
                    str(SCRIPT),
                    "--gh",
                    str(self.fake_gh),
                    hook,
                ])
                + ' "$@"\n',
                encoding="utf-8",
            )
            entry.chmod(0o700)
        self.git("config", "--global", "core.hooksPath", str(self.hooks))
        self.git("remote", "add", "origin", str(self.remote))

    def git(
        self,
        *args: str,
        check: bool = True,
        data: bytes | None = None,
        extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[bytes]:
        """Run Git using only this fixture's global configuration.

        Returns:
            Captured process status and output.

        """
        result = subprocess.run(
            ["git", *args],
            cwd=self.repo,
            env=self.env | (extra_env or {}),
            input=data,
            capture_output=True,
            check=False,
        )
        if check and result.returncode:
            self.fail(result.stderr.decode())
        return result

    def stage(self, text: str) -> None:
        """Stage a file with the supplied content."""
        (self.repo / "content.txt").write_text(text, encoding="utf-8")
        self.git("add", "content.txt")

    def commit(self, message: str = "fixture", *, bypass: bool = False) -> None:
        """Create a commit, optionally simulating an unprotected client."""
        self.git(
            *(["-c", "core.hooksPath=/dev/null"] if bypass else []),
            "commit",
            "--allow-empty",
            "-m",
            message,
        )

    def blocked(self, result: subprocess.CompletedProcess[bytes]) -> None:
        """Assert rejection without exposing the matching private value."""
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(PRIVATE.encode(), result.stdout + result.stderr)
        self.assertIn(b"priv", result.stderr.lower())

    def test_new_repository_without_remote_uses_public_identity(self) -> None:
        """A first commit needs no remote to select the public address."""
        self.git("remote", "remove", "origin")
        self.commit()
        self.assertEqual(
            self.git("log", "-1", "--format=%ae%n%ce").stdout.decode().splitlines(),
            [PUBLIC, PUBLIC],
        )

    def test_init_and_clone_with_global_hooks_already_installed(self) -> None:
        """Initialization must work before the new repository has a HEAD file."""
        self.git("init", str(self.root / "new-repository"))
        self.git("init", "--bare", str(self.root / "new-bare.git"))
        self.commit()
        self.git("clone", str(self.repo), str(self.root / "clone"))

    def test_author_and_committer_environment_overrides(self) -> None:
        """Explicit private identity overrides cannot bypass the hook."""
        for variable in ["GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL"]:
            with self.subTest(variable=variable):
                self.blocked(
                    self.git(
                        "commit",
                        "--allow-empty",
                        "-m",
                        "fixture",
                        check=False,
                        extra_env={variable: PRIVATE},
                    )
                )

    def test_staged_content_encodings_and_chunk_boundary(self) -> None:
        """Catch common escaping, case changes, and a streaming boundary."""
        for value in [
            PRIVATE,
            PRIVATE.upper(),
            PRIVATE.replace("@", "\\@"),
            PRIVATE.replace("@", "%40"),
            PRIVATE.replace("@", "&#64;"),
            "x" * (1024 * 1024 - 5) + PRIVATE,
            "fallback@example.invalid",
        ]:
            self.stage(value)
            self.blocked(self.git("commit", "-m", "fixture", check=False))

    def test_commit_message_and_local_hook_mutation(self) -> None:
        """Check trailers and the message after an existing hook edits it."""
        self.blocked(
            self.git(
                "commit",
                "--allow-empty",
                "-m",
                "Co-authored-by: " + PRIVATE,
                check=False,
            )
        )
        local = self.repo / ".git/hooks/commit-msg"
        local.write_text(
            '#!/bin/sh\nprintf "%s\\n" ' + shlex.quote(PRIVATE) + ' >> "$1"\n',
            encoding="utf-8",
        )
        local.chmod(0o700)
        self.blocked(self.git("commit", "--allow-empty", "-m", "clean", check=False))

    def test_plaintext_filename(self) -> None:
        """File names are published data, too."""
        (self.repo / PRIVATE).touch()
        self.git("add", PRIVATE)
        self.blocked(self.git("commit", "-m", "fixture", check=False))

    def test_deleted_historical_blob_is_blocked_on_push(self) -> None:
        """A clean latest tree cannot conceal an outgoing historical leak."""
        self.stage(PRIVATE)
        self.commit(bypass=True)
        self.git("rm", "content.txt")
        self.commit()
        self.blocked(self.git("push", "origin", "main", check=False))
        self.assertEqual(
            self.git("--git-dir", str(self.remote), "show-ref", check=False).returncode,
            1,
        )

    def test_ancestor_identity_and_tag_message(self) -> None:
        """Scan all outgoing metadata, including annotated tags."""
        self.git(
            "-c",
            "core.hooksPath=/dev/null",
            "commit",
            "--allow-empty",
            "-m",
            "old",
            extra_env={"GIT_AUTHOR_EMAIL": PRIVATE},
        )
        self.commit()
        self.blocked(self.git("push", "origin", "main", check=False))
        self.git("tag", "-a", "test-tag", "-m", PRIVATE)
        self.blocked(self.git("push", "origin", "test-tag", check=False))

    def test_clean_push_preserves_legacy_stdin_and_post_commit_hook(self) -> None:
        """Existing repository hooks receive their original arguments and input."""
        local = self.repo / ".git/hooks/pre-push"
        local.write_text(
            '#!/bin/sh\ncat > push-input\nprintf "%s" "$1" > push-remote\n',
            encoding="utf-8",
        )
        local.chmod(0o700)
        post = self.repo / ".git/hooks/post-commit"
        post.write_text("#!/bin/sh\ntouch post-marker\n", encoding="utf-8")
        post.chmod(0o700)
        self.stage("safe")
        self.commit()
        self.git("push", "origin", "main")
        self.assertTrue((self.repo / "post-marker").exists())
        self.assertEqual(
            (self.repo / "push-remote").read_text(encoding="utf-8"), "origin"
        )
        self.assertIn(b"refs/heads/main", (self.repo / "push-input").read_bytes())

    def test_remote_existing_history_and_stale_tracking_refs(self) -> None:
        """Already published history is excluded only while the server has it."""
        self.stage(PRIVATE)
        self.commit(bypass=True)
        bad = self.git("rev-parse", "HEAD").stdout.decode().strip()
        self.git("-c", "core.hooksPath=/dev/null", "push", "origin", "main")
        self.stage("safe")
        self.commit()
        self.git("push", "origin", "main")
        self.git("--git-dir", str(self.remote), "update-ref", "-d", "refs/heads/main")
        self.git("update-ref", "refs/remotes/origin/stale", bad)
        self.blocked(self.git("push", "origin", "main", check=False))

    def test_private_repository_exception_and_visibility_failure(self) -> None:
        """Allow explicit private content, while always blocking private metadata."""
        self.git(
            "remote",
            "set-url",
            "origin",
            "git@github.com:test-owner/private-project.git",
        )
        self.stage(PRIVATE)
        self.commit()
        self.blocked(
            self.git(
                "commit",
                "--allow-empty",
                "-m",
                "fixture",
                check=False,
                extra_env={"GIT_COMMITTER_EMAIL": PRIVATE},
            )
        )
        self.fake_gh.write_text(
            "#!/bin/sh\nprintf '{\"private\":false}\\n'\n", encoding="utf-8"
        )
        self.blocked(self.git("commit", "--allow-empty", "-m", "fixture", check=False))
        self.fake_gh.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
        self.blocked(self.git("commit", "--allow-empty", "-m", "fixture", check=False))
        self.git("remote", "set-url", "origin", str(self.remote))
        self.blocked(self.git("push", "origin", "main", check=False))

    def test_missing_policy_and_recursive_hook_fail_closed(self) -> None:
        """Missing secrets and accidental wrapper loops cannot silently disable checks."""
        self.policy.unlink()
        self.blocked(self.git("commit", "--allow-empty", "-m", "fixture", check=False))
        local = self.repo / ".git/hooks/pre-commit"
        local.symlink_to(self.hooks / "pre-commit")
        result = self.git("commit", "--allow-empty", "-m", "fixture", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"Recursive", result.stderr)

    def test_blob_tag_and_large_clean_content(self) -> None:
        """Git tags may point directly to blobs; those still require inspection."""
        self.stage("x" * (2 * 1024 * 1024))
        self.commit()
        self.git("push", "origin", "main")
        blob = (
            self
            .git("hash-object", "-w", "--stdin", data=PRIVATE.encode())
            .stdout.decode()
            .strip()
        )
        self.git("tag", "blob-tag", blob)
        self.blocked(self.git("push", "origin", "blob-tag", check=False))


if __name__ == "__main__":
    unittest.main()
