"""Check a generated import link without using a real credential."""

from __future__ import annotations

import argparse
import os
import stat
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Run the explicitly supplied tmpfiles executable.
import tempfile
from pathlib import Path

PRIVATE_DIRECTORY_MODE = 0o700
PRIVATE_FILE_MODE = 0o400


def check(rules: Path, tmpfiles: str) -> None:
    """Exercise creation, generation changes and reboot recreation."""
    assert os.getuid() != 0, "The import fixture must run as an ordinary user"
    with tempfile.TemporaryDirectory(prefix="refined-import-") as temporary:
        runtime = Path(temporary)
        sealed = runtime / "sealed fixture"
        template = Path("templates/import fixture")
        for number in (1, 2):
            generation = sealed / f"generation-{number}"
            destination = generation / template
            destination.parent.mkdir(parents=True)
            destination.write_text(f'{{"fixture": {number}}}', encoding="utf-8")
            destination.chmod(PRIVATE_FILE_MODE)
        current = sealed / "current"
        current.symlink_to("generation-1")
        alias = sealed / "refined-github-token-import.json"
        assert not alias.exists(), "The original missing-path failure must reproduce"
        environment = os.environ | {
            "XDG_RUNTIME_DIR": str(runtime),
            "SYSTEMD_LOG_TARGET": "console",
            "SYSTEMD_LOG_LEVEL": "debug",
            "SYSTEMD_LOG_COLOR": "0",
        }

        def create() -> None:
            try:
                subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] -- Argument vector, synthetic fixture, no shell.
                    [tmpfiles, "--user", "--create", str(rules)],
                    env=environment,
                    check=True,
                    capture_output=True,
                    text=True,
                )
            except subprocess.CalledProcessError as error:
                error.add_note(
                    f"Synthetic rules: {rules.read_text(encoding='utf-8')!r}"
                )
                error.add_note(f"stdout={error.stdout!r}; stderr={error.stderr!r}")
                raise

        create()
        assert alias.is_symlink(), "The import must not duplicate plaintext"
        assert alias.read_text(encoding="utf-8") == '{"fixture": 1}'
        assert stat.S_IMODE(sealed.stat().st_mode) == PRIVATE_DIRECTORY_MODE
        assert stat.S_IMODE(alias.stat().st_mode) == PRIVATE_FILE_MODE
        assert alias.stat().st_uid == os.getuid()

        replacement = sealed / "next"
        replacement.symlink_to("generation-2")
        replacement.replace(current)
        assert alias.read_text(encoding="utf-8") == '{"fixture": 2}'
        alias.unlink()
        create()
        create()
        assert alias.read_text(encoding="utf-8") == '{"fixture": 2}'
        for number in (1, 2):
            original = sealed / f"generation-{number}" / template
            assert original.read_text(encoding="utf-8") == f'{{"fixture": {number}}}'
            assert stat.S_IMODE(original.stat().st_mode) == PRIVATE_FILE_MODE


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rules", type=Path, required=True)
    parser.add_argument("--tmpfiles", required=True)
    arguments = parser.parse_args()
    check(arguments.rules, arguments.tmpfiles)
