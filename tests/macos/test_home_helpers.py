"""Behavior tests for the macOS Home Manager command-line helpers."""

from __future__ import annotations

import hashlib
import os
import plistlib
import stat
import subprocess  # ruff:ignore[suspicious-subprocess-import]
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_DIRECTORY = Path(os.environ["MACOS_HOME_MODULE_DIRECTORY"])


class MacOSHomeHelperTests(unittest.TestCase):
    """Exercise helper behavior through each command-line interface."""

    def test_dock_state_uses_defaults_adapter_and_ignores_unmanaged_fields(
        self,
    ) -> None:
        """Only user-visible managed Dock fields contribute to the state hash."""
        fixture = {
            "persistent-apps": [
                {
                    "GUID": 123,
                    "tile-type": "file-tile",
                    "tile-data": {
                        "file-data": {
                            "_CFURLString": "file:///Applications/Safari.app/"
                        }
                    },
                }
            ],
            "persistent-others": [],
            "recent-apps": [{"GUID": 999}],
        }
        expected_json = (
            b'{"persistent-apps":[{"arrangement":null,"displayas":null,'
            b'"showas":null,"tile-type":"file-tile",'
            b'"url":"file:///Applications/Safari.app/"}],"persistent-others":[]}'
        )

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            plist_path = temporary_path / "dock.plist"
            plist_path.write_bytes(plistlib.dumps(fixture))
            defaults_adapter = temporary_path / "defaults"
            defaults_adapter.write_text(
                f"#!{sys.executable}\n"
                "import os, sys\n"
                "with open(os.environ['DOCK_TEST_PLIST'], 'rb') as stream:\n"
                "    sys.stdout.buffer.write(stream.read())\n",
                encoding="utf-8",
            )
            defaults_adapter.chmod(defaults_adapter.stat().st_mode | stat.S_IXUSR)

            environment = os.environ.copy()
            environment["DOCK_DEFAULTS_BIN_OVERRIDE"] = str(defaults_adapter)
            environment["DOCK_TEST_PLIST"] = str(plist_path)
            result = subprocess.run(  # ruff:ignore[subprocess-without-shell-equals-true]
                [sys.executable, str(MODULE_DIRECTORY / "dock_state.py")],
                check=False,
                capture_output=True,
                text=True,
                env=environment,
            )

        self.assertEqual(  # ruff:ignore[pytest-unittest-assertion]
            result.returncode, 0, msg=result.stderr
        )
        self.assertEqual(  # ruff:ignore[pytest-unittest-assertion]
            result.stdout.strip(), hashlib.sha256(expected_json).hexdigest()
        )


if __name__ == "__main__":
    unittest.main()
