"""Exercise default remote recipes through Just while replacing side-effect tools."""

import json
import os
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Disposable command fixtures.
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).parents[2]


@pytest.mark.parametrize(
    ("recipe", "kind", "arguments"),
    [
        ("macbook-build", "build", ["--log-dir", "a directory with spaces"]),
        ("macbook-deploy", "deploy", ["--dry-activate"]),
        ("mac-check", "check", []),
        ("mac-test", "test", ["-q", "tests/macos/test_mac_source.py"]),
        ("mac-exec", "command", ["printf", "%s", "one argument"]),
        ("darwin-build", "build", ["macbook-pro-m4"]),
        ("darwin-switch", "deploy", ["macbook-pro-m4", "--dry-activate"]),
    ],
)
def test_remote_recipes_default_to_fresh_export(
    tmp_path: Path, recipe: str, kind: str, arguments: list[str]
) -> None:
    """Every existing source-based remote entry point starts the automatic verifier."""
    tools = tmp_path / "bin"
    tools.mkdir()
    body = (ROOT / "tests/macos/fixtures/workflow_recipe.py").read_text()
    for name in ("python3", "uname"):
        path = tools / name
        path.write_text(f"#!{sys.executable}\n" + body)
        path.chmod(0o755)
    record = tmp_path / "arguments.json"
    executable = shutil.which("just")
    assert executable
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Real recipe parsing with owned command stubs.
        [executable, "--justfile", str(ROOT / "justfile"), recipe, *arguments],
        env=os.environ
        | {
            "PATH": str(tools) + os.pathsep + os.environ["PATH"],
            "RECIPE_ARGUMENTS": str(record),
            "FIXTURE_UNAME": "Linux",
        },
        check=True,
        capture_output=True,
    )
    invocation = json.loads(record.read_text())
    assert invocation[0] == str(ROOT / "scripts/mac_source.py")
    assert invocation[1] == "auto"
    assert invocation[invocation.index("--kind") + 1] == kind
    if recipe == "macbook-build":
        assert invocation[-2:] == ["--log-dir", "a directory with spaces"]
