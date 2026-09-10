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
        """Create an isolated identity, policy, configured checks, and destination."""
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
        self._git("init", "--initial-branch=main")
        self._git("init", "--bare", str(self.remote))
        self._git("config", "--global", "user.name", "Fixture")
        self._git("config", "--global", "user.email", PUBLIC)
        self._git("config", "--global", "user.useConfigOnly", "true")
        self._git("config", "--global", "commit.gpgSign", "false")
        self.fake_gh = self.root / "gh"
        self.fake_gh.write_text(
            "#!/bin/sh\nprintf '{\"private\":true}\\n'\n", encoding="utf-8"
        )
        self.fake_gh.chmod(0o700)
        for event in ["commit-msg", "pre-push"]:
            variable = (
                "PRIVACY_COMMIT_COMMAND"
                if event == "commit-msg"
                else "PRIVACY_PUSH_COMMAND"
            )
            if variable in os.environ:
                command = shlex.split(os.environ[variable])
                command[command.index("--policy-file") + 1] = str(self.policy)
                command[command.index("--gh") + 1] = str(self.fake_gh)
            else:
                command = [
                    sys.executable,
                    str(SCRIPT),
                    "--policy-file",
                    str(self.policy),
                    "--gh",
                    str(self.fake_gh),
                    event,
                ]
            self._git("config", "--global", "hook.privacy-" + event + ".event", event)
            self._git(
                "config",
                "--global",
                "hook.privacy-" + event + ".command",
                shlex.join(command),
            )
        self._git("remote", "add", "origin", str(self.remote))

    def _git(
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

    def _stage(self, text: str) -> None:
        """Stage a file with the supplied content."""
        (self.repo / "content.txt").write_text(text, encoding="utf-8")
        self._git("add", "content.txt")

    def _commit(self, message: str = "fixture", *, bypass: bool = False) -> None:
        """Create a commit, optionally simulating an unprotected client."""
        self._git(
            "commit",
            *(["--no-verify"] if bypass else []),
            "--allow-empty",
            "-m",
            message,
        )

    def _blocked(self, result: subprocess.CompletedProcess[bytes]) -> None:
        """Assert rejection without exposing the matching private value."""
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(PRIVATE.encode(), result.stdout + result.stderr)
        self.assertIn(b"priv", result.stderr.lower())

    def test_new_repository_without_remote_uses_public_identity(self) -> None:
        """A first commit needs no remote to select the public address."""
        self._git("remote", "remove", "origin")
        self._commit()
        self.assertEqual(
            self._git("log", "-1", "--format=%ae%n%ce").stdout.decode().splitlines(),
            [PUBLIC, PUBLIC],
        )

    def test_init_and_clone_with_global_hooks_already_installed(self) -> None:
        """Initialization must work before the new repository has a HEAD file."""
        self._git("init", str(self.root / "new-repository"))
        self._git("init", "--bare", str(self.root / "new-bare.git"))
        self._commit()
        self._git("clone", str(self.repo), str(self.root / "clone"))

    def test_author_and_committer_environment_overrides(self) -> None:
        """Explicit private identity overrides cannot bypass the hook."""
        for variable in ["GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL"]:
            with self.subTest(variable=variable):
                self._blocked(
                    self._git(
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
            self._stage(value)
            self._blocked(self._git("commit", "-m", "fixture", check=False))

    def test_commit_message_and_local_hook_mutation(self) -> None:
        """Check trailers immediately and catch later hook mutations before publishing."""
        self._blocked(
            self._git(
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
        self._commit("clean")
        self._blocked(self._git("push", "origin", "main", check=False))

    def test_plaintext_filename(self) -> None:
        """File names are published data, too."""
        (self.repo / PRIVATE).touch()
        self._git("add", PRIVATE)
        self._blocked(self._git("commit", "-m", "fixture", check=False))

    def test_deleted_historical_blob_is_blocked_on_push(self) -> None:
        """A clean latest tree cannot conceal an outgoing historical leak."""
        self._stage(PRIVATE)
        self._commit(bypass=True)
        self._git("rm", "content.txt")
        self._commit()
        self._blocked(self._git("push", "origin", "main", check=False))
        self.assertEqual(
            self._git(
                "--git-dir", str(self.remote), "show-ref", check=False
            ).returncode,
            1,
        )

    def test_ancestor_identity(self) -> None:
        """Scan all outgoing metadata, including an ancestor author."""
        self._git(
            "commit",
            "--no-verify",
            "--allow-empty",
            "-m",
            "old",
            extra_env={"GIT_AUTHOR_EMAIL": PRIVATE},
        )
        self._commit()
        self._blocked(self._git("push", "origin", "main", check=False))

    def test_tag_message_on_clean_history(self) -> None:
        """A tag message is rejected independently of any private ancestor."""
        self._commit()
        self._git("push", "origin", "main")
        self._git("tag", "-a", "test-tag", "-m", PRIVATE)
        self._blocked(self._git("push", "origin", "test-tag", check=False))

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
        self._stage("safe")
        self._commit()
        self._git("push", "origin", "main")
        self.assertTrue((self.repo / "post-marker").exists())
        self.assertEqual(
            (self.repo / "push-remote").read_text(encoding="utf-8"), "origin"
        )
        self.assertIn(b"refs/heads/main", (self.repo / "push-input").read_bytes())

    def test_remote_existing_history_and_stale_tracking_refs(self) -> None:
        """Already published history is excluded only while the server has it."""
        self._stage(PRIVATE)
        self._commit(bypass=True)
        bad = self._git("rev-parse", "HEAD").stdout.decode().strip()
        self._git("push", "--no-verify", "origin", "main")
        self._stage("safe")
        self._commit()
        self._git("push", "origin", "main")
        self._git("--git-dir", str(self.remote), "update-ref", "-d", "refs/heads/main")
        self._git("update-ref", "refs/remotes/origin/stale", bad)
        self._blocked(self._git("push", "origin", "main", check=False))

    def test_private_repository_exception_and_visibility_failure(self) -> None:
        """Allow explicit private content, while always blocking private metadata."""
        self._git(
            "remote",
            "set-url",
            "origin",
            "git@github.com:test-owner/private-project.git",
        )
        self._stage(PRIVATE)
        self._commit()
        self._blocked(
            self._git(
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
        self._commit()
        self.fake_gh.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
        self._commit()
        self._git("remote", "set-url", "origin", str(self.remote))
        self._blocked(self._git("push", "origin", "main", check=False))

    def test_private_publication_requires_live_private_visibility(self) -> None:
        """Only a confirmed private destination may receive exempt file content."""
        self._stage(PRIVATE)
        self._commit(bypass=True)
        oid = self._git("rev-parse", "HEAD").stdout.strip()
        command = shlex.split(
            self._git(
                "config", "--global", "hook.privacy-pre-push.command"
            ).stdout.decode()
        )
        # Keep real object plumbing but route remote discovery to the local fixture.
        fake_git = self.root / "git-wrapper"
        fake_git.write_text(
            '#!/bin/sh\nif test "$1" = ls-remote; then\n'
            "  exec git ls-remote --refs "
            + shlex.quote(str(self.remote))
            + "\n"
            + 'fi\nexec git "$@"\n',
            encoding="utf-8",
        )
        fake_git.chmod(0o700)
        if "--git" in command:
            command[command.index("--git") + 1] = str(fake_git)
        else:
            command[-1:-1] = ["--git", str(fake_git)]
        for response, permitted in [
            ("printf '{\"private\":true}\\n'", True),
            ("printf '{\"private\":false}\\n'", False),
            ("exit 1", False),
        ]:
            with self.subTest(response=response):
                self.fake_gh.write_text(
                    "#!/bin/sh\n" + response + "\n", encoding="utf-8"
                )
                result = subprocess.run(
                    [
                        *command,
                        "origin",
                        "git@github.com:test-owner/private-project.git",
                    ],
                    cwd=self.repo,
                    env=self.env,
                    capture_output=True,
                    check=False,
                    input=b"refs/heads/main "
                    + oid
                    + b" refs/heads/main "
                    + ZERO.encode()
                    + b"\n",
                )
                if permitted:
                    self.assertEqual(result.returncode, 0, result.stderr.decode())
                else:
                    self._blocked(result)

    def test_missing_policy_fails_closed(self) -> None:
        """Missing secrets cannot silently disable checks."""
        self.policy.unlink()
        self._blocked(
            self._git("commit", "--allow-empty", "-m", "fixture", check=False)
        )

    def test_custom_hook_directory_does_not_disable_privacy(self) -> None:
        """A repository hook manager cannot displace configured privacy checks."""
        custom = self.root / "custom-hooks"
        custom.mkdir()
        self._git("config", "--local", "core.hooksPath", str(custom))
        self._stage(PRIVATE)
        self._blocked(self._git("commit", "-m", "fixture", check=False))
        self._commit(bypass=True)
        self._blocked(self._git("push", "origin", "main", check=False))

    def test_nested_checkout_hooks_keep_working(self) -> None:
        """An ordinary hook can invoke another repository's checkout hook."""
        self._commit()
        child = self.root / "child"
        self._git("clone", str(self.repo), str(child))
        nested = child / ".git/hooks/post-checkout"
        nested.write_text("#!/bin/sh\ntouch nested-marker\n", encoding="utf-8")
        nested.chmod(0o700)
        parent = self.repo / ".git/hooks/post-checkout"
        parent.write_text(
            "#!/bin/sh\nunset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE\ngit -C "
            + shlex.quote(str(child))
            + " checkout main\n",
            encoding="utf-8",
        )
        parent.chmod(0o700)
        self._git("checkout", "main")
        self.assertTrue((child / "nested-marker").exists())

    def test_replacement_refs_cannot_hide_original_private_objects(self) -> None:
        """Publication examines the original data despite a clean local replacement."""
        self._commit()
        clean = self._git("rev-parse", "HEAD").stdout.decode().strip()
        self._commit(PRIVATE, bypass=True)
        original = self._git("rev-parse", "HEAD").stdout.decode().strip()
        self._git("replace", original, clean)
        self._blocked(self._git("push", "origin", "main", check=False))

    def test_blob_tag_and_large_clean_content(self) -> None:
        """Git tags may point directly to blobs; those still require inspection."""
        self._stage("x" * (2 * 1024 * 1024))
        self._commit()
        self._git("push", "origin", "main")
        blob = (
            self
            ._git("hash-object", "-w", "--stdin", data=PRIVATE.encode())
            .stdout.decode()
            .strip()
        )
        self._git("tag", "blob-tag", blob)
        self._blocked(self._git("push", "origin", "blob-tag", check=False))


if __name__ == "__main__":
    unittest.main()
