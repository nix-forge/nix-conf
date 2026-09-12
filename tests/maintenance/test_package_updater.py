"""Keep the root updater entry point compatible with the package repository."""

from __future__ import annotations

import json
import runpy
import shutil
import sys
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from collections.abc import Sequence

ROOT = Path(__file__).resolve().parents[2]


@pytest.mark.parametrize("exit_code", [0, 7])
def test_forward_package_update(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    exit_code: int,
) -> None:
    """Forward arguments and the delegate's exit status from any working directory."""
    entry = tmp_path / "scripts/update-packages.py"
    entry.parent.mkdir()
    shutil.copyfile(ROOT / "scripts/update-packages.py", entry)
    delegate = tmp_path / "pkgs/scripts/update-packages.py"
    delegate.parent.mkdir(parents=True)
    delegate.write_text(
        "import json, sys\n"
        "print(json.dumps(sys.argv[1:]))\n"
        f"raise SystemExit({exit_code})\n",
        encoding="utf-8",
    )
    arguments: Sequence[str] = ["--package", "fixture", "--", "--dry-run"]
    monkeypatch.setattr(sys, "argv", [str(entry), *arguments])
    monkeypatch.chdir(tmp_path.parent)

    with pytest.raises(SystemExit) as result:
        runpy.run_path(str(entry), run_name="__main__")

    assert result.value.code == exit_code
    assert json.loads(capsys.readouterr().out) == list(arguments)
