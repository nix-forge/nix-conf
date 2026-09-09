"""Check patch application, an already-fixed source, and unfamiliar upstream edits."""

import pathlib
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Run only the local test executable or pinned patch helper.
import sys
import tempfile

source, helper, patch = map(pathlib.Path, sys.argv[1:])
relative = pathlib.Path("external/crashpad/client/crash_report_database_generic.cc")
with tempfile.TemporaryDirectory() as temporary:
    root = pathlib.Path(temporary)
    target = root / relative
    target.parent.mkdir(parents=True)
    target.write_bytes((source / relative).read_bytes())
    command = ["bash", str(helper), str(patch)]
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Arguments are fixture paths, never shell text.
        command, cwd=root, check=True
    )
    fixed = target.read_bytes()
    second = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Arguments are fixture paths, never shell text.
        command, cwd=root, capture_output=True, text=True, check=True
    )
    if "already present" not in second.stdout or target.read_bytes() != fixed:
        message = (
            "FAIL: an upstream-applied fix must be skipped without modifying source"
        )
        sys.exit(message)
    # A source refactor cannot silently drop the fix or apply a partial patch.
    target.write_bytes(
        fixed.replace(b"ScopedFileHandle lock_fd", b"ScopedFileHandle changed_fd")
    )
    unfamiliar = target.read_bytes()
    third = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Arguments are fixture paths, never shell text.
        command, cwd=root, capture_output=True, text=True, check=False
    )
    if third.returncode == 0 or target.read_bytes() != unfamiliar:
        message = "FAIL: unfamiliar source must require review without modifying source"
        sys.exit(message)
    print("PASS: patch applies, skips an existing fix, and rejects unfamiliar source")  # ruff: ignore[print] - Report the check result to the build log.
