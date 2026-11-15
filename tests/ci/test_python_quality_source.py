"""Check cache invalidation through the production Python fileset declaration."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
pytestmark = pytest.mark.nix_daemon


@pytest.mark.parametrize(
    ("name", "invalidate"),
    [
        ("new-tree/helper.py", True),
        ("new-tree/types.pyi", True),
        ("templates/new/helper.py.in", True),
        ("new-tree/pyproject.toml", True),
        ("new-tree/.ruff.toml", True),
        ("new-tree/ty.toml", True),
        ("new-tree/.gitignore", True),
        ("docs/guide.md", False),
        ("site/image.png", False),
        ("pkgs/helper.py", False),
    ],
)
def test_quality_source_invalidation(
    tmp_path: Path, name: str, *, invalidate: bool
) -> None:
    """New Python/config inputs change the real source path; unrelated files do not."""
    root = tmp_path / "source"
    root.mkdir()
    for directory in ("pkgs", "nix-config-framework", "nix-homelab", "nix-seal"):
        (root / directory).mkdir()
    (root / "pyproject.toml").write_text("[tool.ruff]\n")
    expression = (
        f"toString (import {ROOT}/flake/dev/python-quality-source.nix {{ "
        f"lib = import {os.environ['NIX_TEST_NIXPKGS']}/lib; "
        f"root = {root}; }})"
    )

    def source_path() -> str:
        return json.loads(
            subprocess.check_output(
                [
                    "nix",
                    "eval",
                    "--offline",
                    "--store",
                    str(tmp_path / "store"),
                    "--impure",
                    "--json",
                    "--expr",
                    expression,
                ],
                text=True,
            )
        )

    before = source_path()
    added = root / name
    added.parent.mkdir(parents=True, exist_ok=True)
    added.write_text("# A new source or configuration input.\n")
    after_addition = source_path()
    assert (before != after_addition) == invalidate
    added.write_text("# Changed input.\n")
    assert (after_addition != source_path()) == invalidate


def test_hosted_inventory_keeps_local_checks_and_single_ci_owner(
    tmp_path: Path,
) -> None:
    """Evaluate the exported inventory against additions through its real consumer."""
    expression = f"""
      let
        self = {{
          checks.x86_64-linux = {{
            pre-commit = "hooks";
            python-quality = "python";
            javascript-quality = "js";
            stylesheet-quality = "css";
            swift-quality = "swift";
            lua-quality = "lua";
            treefmt = "format";
            documentation = "docs";
            gitleaks-policy = "secrets";
          }};
          inherit (module.flake) lintChecks;
        }};
        module = import {ROOT}/flake/lint-checks.nix {{
          inherit self;
          lib.optionalAttrs = condition: value: if condition then value else {{}};
        }};
      in {{
        local = builtins.attrNames module.flake.lintChecks.x86_64-linux;
        hosted = builtins.attrNames module.flake.hostedLintChecks.x86_64-linux;
      }}
    """
    inventory = json.loads(
        subprocess.check_output(
            [
                "nix",
                "eval",
                "--offline",
                "--impure",
                "--store",
                str(tmp_path / "store"),
                "--json",
                "--expr",
                expression,
            ],
            text=True,
        )
    )
    assert set(inventory["local"]) - set(inventory["hosted"]) == {
        "pre-commit",
        "python-quality",
    }
    assert "gitleaks-policy" in inventory["hosted"]
