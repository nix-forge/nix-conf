"""Navidrome plugin scopes require account IDs, even for named listeners."""

import json
import shutil
import subprocess
import unittest
from pathlib import Path

SCRIPT = (
    Path(__file__).resolve().parents[3]
    / "hosts/nixos/desktop/local/homelab/music/scripts/resolve-navidrome-plugin-user-ids.sh"
)


class PluginUserIdsTest(unittest.TestCase):
    """Check a restricted plugin scope against a Navidrome user listing."""

    def setUp(self) -> None:
        """Use distinct account IDs and usernames, as Navidrome does."""
        bash = shutil.which("bash")
        assert bash is not None
        self.bash = bash
        self.accounts = [
            {"id": "listener-id-42", "username": "listener"},
            {"id": "feishin-id-17", "username": "feishin"},
            {"id": "admin-id-1", "username": "admin"},
        ]

    def run_resolver(
        self, accounts: list[dict[str, str]]
    ) -> subprocess.CompletedProcess[str]:
        """Feed a disposable account listing to the resolver.

        Returns:
            The command result, including its exit code and output.

        """
        return subprocess.run(
            [self.bash, str(SCRIPT), "listener", "feishin"],
            input=json.dumps(accounts),
            text=True,
            capture_output=True,
            check=False,
        )

    def test_returns_ids_for_exact_managed_usernames(self) -> None:
        """Pass account IDs to plugin permissions rather than usernames."""
        result = self.run_resolver(self.accounts)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["listener-id-42", "feishin-id-17"])

    def test_refuses_missing_or_ambiguous_accounts(self) -> None:
        """Do not leave a plugin enabled with an incomplete access scope."""
        for accounts in (
            self.accounts[:1],
            [*self.accounts, {"id": "other-id", "username": "listener"}],
        ):
            with self.subTest(accounts=accounts):
                result = self.run_resolver(accounts)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
