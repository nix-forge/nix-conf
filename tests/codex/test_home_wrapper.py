"""Exercise real Nix-generated CLI wrappers and the managed child environment."""

from __future__ import annotations

import json
import os
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Exercise the Nix-built CLI entry point.
from pathlib import Path

import pytest

EXPECTED_EXIT = 23

pytestmark = pytest.mark.nix_integration


@pytest.fixture(params=["xdg", "legacy"])
def selected(request: pytest.FixtureRequest) -> dict:
    """Load the actual evaluated module's fixture variant.

    Returns:
        The selected generated-command and child-policy fixture.

    """
    return json.loads(
        Path(os.environ["CODEX_HOME_MANIFEST"]).read_text(encoding="utf-8")
    )[request.param]


@pytest.mark.parametrize("choice", ["unset", "empty", "explicit"])
def test_home_selection_and_arguments(
    selected: dict, choice: str, tmp_path: Path
) -> None:
    """Defaults survive stripped environments while explicit homes and argv survive."""
    legacy = tmp_path / "home/.codex"
    alternate = tmp_path / "alternate 'quoted' $state"
    legacy.mkdir(parents=True)
    alternate.mkdir()
    for directory in (legacy, alternate):
        (directory / "preserve.txt").write_text("keep original store", encoding="utf-8")
    environment = {"HOME": str(legacy.parent), "PATH": os.environ["PATH"]}
    if choice != "unset":
        environment["CODEX_HOME"] = str(alternate) if choice == "explicit" else ""
    arguments = [
        "queue",
        "space argument",
        "quote'\"$literal",
        "line\nbreak",
        "--fixture-fail",
    ]
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Explicit argv from the evaluated fixture.
        [selected["binary"], *arguments],
        env=environment,
        shell=False,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == EXPECTED_EXIT
    assert json.loads(result.stdout) == {
        "home": str(alternate) if choice == "explicit" else selected["home"],
        "desktopApp": selected["desktopApp"],
        "argv": arguments,
    }
    assert sorted(p.name for p in legacy.iterdir()) == ["preserve.txt"]
    assert sorted(p.name for p in alternate.iterdir()) == ["preserve.txt"]
    assert all(
        (p / "preserve.txt").read_text(encoding="utf-8") == "keep original store"
        for p in (legacy, alternate)
    )


@pytest.mark.parametrize("variant", ["xdg", "legacy", "gui"])
def test_managed_core_child_policy(variant: str) -> None:
    """The exact evaluated core policy carries the home even to a raw backend."""
    selected = json.loads(
        Path(os.environ["CODEX_HOME_MANIFEST"]).read_text(encoding="utf-8")
    )[variant]
    policy = selected["policy"]
    assert policy["inherit"] == "core"
    assert policy["exclude"] == ["*TOKEN*", "*SECRET*"]
    assert policy["set"]["PRESERVED_SETTING"] == "fixture"
    environment = {"PATH": os.environ["PATH"], **policy["set"]}
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Explicit argv from the evaluated fixture.
        [selected["raw"], "child"],
        env=environment,
        shell=False,
        capture_output=True,
        text=True,
        check=True,
    )
    assert json.loads(result.stdout)["home"] == selected["home"]
