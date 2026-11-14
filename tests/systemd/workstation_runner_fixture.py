"""Adapt only synthetic admission inputs for tiny native scope probes."""

import os
import re
import shlex
import sys
from pathlib import Path

DISK_ADMISSION_CALLS = 2  # Nested and ordinary payload paths.


def main() -> None:
    """Copy the actual runner with private capacity and a finite admission wait."""
    source = Path(sys.argv[1]).read_text(encoding="utf-8")
    destination = Path(sys.argv[2])
    meminfo = Path(sys.argv[3])
    source, count = re.subn(
        r"--meminfo (?:'[^']*'|\"[^\"]*\"|[^\s]+)(?= --root )",
        "--meminfo " + shlex.quote(str(meminfo)),
        source,
    )
    assert count == 1, "The real controller must consume the fixture snapshot"
    source, count = re.subn(
        r"^admission_timeout=\d+$", "admission_timeout=10", source, flags=re.MULTILINE
    )
    assert count == 1, "The fixture admission deadline must remain bounded"
    source, count = re.subn(
        r"--healthy-seconds \d+", "--healthy-seconds 0", source, count=1
    )
    assert count == 1, "Only the admission controller's healthy interval is adapted"
    if "--adapt-storage" in sys.argv[4:]:
        command = os.environ["WORKSTATION_TEST_DISK_COMMAND"]
        assert "/nix/store/" in command
        assert source.count(command) == DISK_ADMISSION_CALLS
        # Storage capacity has its own owning checks. This VM proves scopes,
        # not the desktop filesystem layout and its production free-space floors.
        source = source.replace(command, "true")
    destination.write_text(source, encoding="utf-8")
    destination.chmod(0o700)


if __name__ == "__main__":
    main()
