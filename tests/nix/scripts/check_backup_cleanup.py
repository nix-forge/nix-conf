"""Exercise generated privileged cleanup in an isolated filesystem fixture."""

from __future__ import annotations

import json
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Runs a generated Bash fixture.
import sys
import tempfile
from pathlib import Path


def main() -> None:
    """Remove only transitional overrides across all backup job kinds."""
    bash = shutil.which("bash")
    assert bash is not None
    policy = Path(sys.argv[1])
    manifest = json.loads((policy / "manifest.json").read_text())
    source = (policy / "backup-policy-cleanup.sh").read_text()
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        control = root / "control"
        runtime = root / "runtime"
        expected = []
        preserved = []
        for job in manifest["backups"]:
            if not job.startswith("desktop-"):
                continue
            destination = job.removeprefix("desktop-")
            units = [
                f"restic-backups-{job}.service",
                f"desktop-backup-verify-{destination}.service",
                f"desktop-backup-cold-{destination}.service",
            ]
            for unit in units:
                paths = [
                    control / f"{unit}.d/80-recurring-memory-fix.conf",
                    control / f"{unit}.d/90-backup-policy-preview.conf",
                    runtime / f"{unit}.d/90-maintenance-stop.conf",
                ]
                expected.extend(paths)
                preserved.append(control / f"{unit}.d/operator.conf")
        assert expected, "No backup jobs were exercised"
        preserved.append(control / "unrelated.service.d/80-recurring-memory-fix.conf")
        for path in expected + preserved:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("preserve fixture bytes\n")
        source = source.replace("/etc/systemd/system.control/", f"{control}/")
        source = source.replace("/run/systemd/system/", f"{runtime}/")
        assert "/etc/" not in source
        assert "/run/" not in source
        script = root / "cleanup.sh"
        script.write_text(source)
        for _ in range(2):
            subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Resolved Bash and private generated fixture, no shell arguments.
                [bash, str(script)], check=True
            )
            assert not [path for path in expected if path.exists()]
            assert all(
                path.read_text() == "preserve fixture bytes\n" for path in preserved
            )


if __name__ == "__main__":
    main()
