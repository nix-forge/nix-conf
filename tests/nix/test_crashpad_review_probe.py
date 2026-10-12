"""Require the review driver to distinguish precise contention from other failures."""

import os
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Execute the repository probe with an inert test adapter.
import sys
import tempfile
import unittest
from pathlib import Path


class ReviewProbeTests(unittest.TestCase):
    """Exercise the actual driver through its subprocess interface."""

    def test_expected_contention(self) -> None:
        """Admission must reject generic failure, quiet baseline and unrelated errors."""
        cases = [
            (False, "", 0, 0),
            (True, "report.lock: File exists", 0, 0),
            (True, "", 0, 1),
            (True, "report.lock: Permission denied", 0, 1),
            (True, "report.lock: File exists\\nother error", 0, 1),
            (True, "report.lock: File exists", 1, 1),
            (False, "report.lock: File exists", 0, 1),
        ]
        for noisy, diagnostic, exit_code, expected in cases:
            with (
                self.subTest(noisy=noisy, diagnostic=diagnostic, exit_code=exit_code),
                tempfile.TemporaryDirectory() as temporary,
            ):
                self._run_probe(Path(temporary), noisy, diagnostic, exit_code, expected)

    def _run_probe(
        self,
        tmp_path: Path,
        noisy: bool,
        diagnostic: str,
        exit_code: int,
        expected: int,
    ) -> None:
        """Validate driver admission; native C++ separately enforces lock invariants."""
        adapter = tmp_path / "native-probe"
        adapter.write_text(
            f"#!{sys.executable}\n"
            "import os, sys\n"
            "mode = sys.argv[2]\n"
            "diagnostic = 'report.lock: Permission denied' if mode == 'denied' else os.environ['PROBE_DIAGNOSTIC']\n"
            "if diagnostic: print(diagnostic.replace('\\\\n', '\\n'), file=sys.stderr)\n"
            "sys.exit(int(os.environ['PROBE_EXIT']))\n"
        )
        adapter.chmod(0o700)
        driver = Path(__file__).parents[2] / "overlays/temporary/tests/crashpad-lock.py"
        command = [sys.executable, str(driver), str(adapter)]
        if noisy:
            command.append("--expect-noisy-contention")
        result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] -- Explicit adapter and driver paths, no shell.
            command,
            env=os.environ
            | {"PROBE_DIAGNOSTIC": diagnostic, "PROBE_EXIT": str(exit_code)},
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(
            result.returncode == 0, expected == 0, result.stdout + result.stderr
        )
