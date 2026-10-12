"""Require quiet contention and visible filesystem errors from the real database."""

import argparse
import pathlib
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Run only the local test executable or pinned patch helper.
import sys
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("binary", type=pathlib.Path)
parser.add_argument("--expect-noisy-contention", action="store_true")
arguments = parser.parse_args()
binary = str(arguments.binary.resolve())
with tempfile.TemporaryDirectory() as temporary:
    for mode in ("pending", "completed", "denied"):
        result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Arguments are fixture paths, never shell text.
            [binary, str(pathlib.Path(temporary) / mode), mode],
            capture_output=True,
            text=True,
            check=True,
        )
        if mode == "denied":
            if "Permission denied" not in result.stderr or ".lock" not in result.stderr:
                message = "FAIL: real lock-file errors must remain visible"
                sys.exit(message)
        elif arguments.expect_noisy_contention:
            diagnostics = result.stderr.splitlines()
            if not diagnostics or not all(
                "File exists" in line and ".lock" in line for line in diagnostics
            ):
                message = (
                    f"FAIL: {mode} did not reproduce lock-file EEXIST:\n{result.stderr}"
                )
                sys.exit(message)
        elif result.stderr:
            message = f"FAIL: {mode} lock contention logged an error:\n{result.stderr}"
            sys.exit(message)
        print(f"PASS: {mode}")  # ruff: ignore[print] - Report the check result to the build log.
