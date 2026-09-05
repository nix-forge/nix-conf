"""Behavior tests for the shared Gecko install-registry repair."""

from __future__ import annotations

import os
import stat
import subprocess  # ruff:ignore[suspicious-subprocess-import]
import sys
import tempfile
import unittest
from pathlib import Path

BROWSER_MODULE_DIRECTORY = Path(os.environ["BROWSER_HOME_MODULE_DIRECTORY"])
HELPER = BROWSER_MODULE_DIRECTORY / "shared" / "reconcile_install_registry.py"


class GeckoInstallRegistryTests(unittest.TestCase):
    """Exercise the shared registry repair through its command-line interface."""

    def test_stale_install_defaults_are_reconciled_without_removing_sections(
        self,
    ) -> None:
        """Every installation should select the managed default profile."""
        profiles_content = """\
[General]
StartWithLastProfile=1

[Profile0]
Default=1
IsRelative=1
Name=default
Path=Profiles/default
"""
        installs_content = """\
[CURRENT]
Default=Profiles/default
Locked=1

[STALE-ONE]
Default=Profiles/old-release
Locked=1

[STALE-TWO]
Default=Profiles/older-release
Locked=1
"""
        expected_content = installs_content.replace(
            "Default=Profiles/old-release", "Default=Profiles/default"
        ).replace("Default=Profiles/older-release", "Default=Profiles/default")

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            profiles_registry = root / "profiles.ini"
            install_registry = root / "installs.ini"
            profiles_registry.write_text(profiles_content, encoding="utf-8")
            install_registry.write_text(installs_content, encoding="utf-8")
            install_registry.chmod(0o600)

            command = [
                sys.executable,
                str(HELPER),
                "--profiles-registry",
                str(profiles_registry),
                "--install-registry",
                str(install_registry),
                "--default-profile",
                "Profiles/default",
            ]
            first = subprocess.run(  # ruff:ignore[subprocess-without-shell-equals-true]
                command,
                check=False,
                capture_output=True,
                text=True,
            )
            second = subprocess.run(  # ruff:ignore[subprocess-without-shell-equals-true]
                command,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(first.returncode, 0, msg=first.stderr)
            self.assertEqual(second.returncode, 0, msg=second.stderr)
            self.assertEqual(
                install_registry.read_text(encoding="utf-8"), expected_content
            )
            self.assertEqual(stat.S_IMODE(install_registry.stat().st_mode), 0o600)
            self.assertEqual(
                first.stdout.strip(), "reconciled 2 stale install mappings"
            )
            self.assertEqual(
                second.stdout.strip(), "install registry is already current"
            )


if __name__ == "__main__":
    unittest.main()
