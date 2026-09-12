"""Preserve source fingerprints while bounding memory for large tracked files."""

from __future__ import annotations

import os
import runpy
import subprocess
import tracemalloc
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import pytest

SOURCE_IDENTITY = runpy.run_path(
    str(Path(__file__).resolve().parents[2] / "scripts/workstation_evidence.py")
)["source_identity"]


def test_streamed_identity_matches_canonical_format(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Retain lock hashes, executable modes, links and deletions with bounded memory."""
    for name in os.environ:
        if name.startswith("GIT_"):
            monkeypatch.delenv(name)
    monkeypatch.setenv("GIT_CONFIG_NOSYSTEM", "1")
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", os.devnull)
    root = tmp_path / "repo"
    root.mkdir()

    def git(*args: str) -> None:
        subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True)

    git("init")
    (root / "flake.lock").write_text("{}\n")
    (root / "deleted").write_text("gone")
    with (root / "large.bin").open("wb") as stream:
        for _ in range(16):
            stream.write(bytes(range(256)) * 4096)
    (root / "large.bin").chmod(0o755)
    (root / "link").symlink_to("large.bin")
    git("add", ".")
    git(
        "-c",
        "user.name=Fixture",
        "-c",
        "user.email=fixture@example.invalid",
        "-c",
        "commit.gpgsign=false",
        "-c",
        "core.hooksPath=/dev/null",
        "commit",
        "-m",
        "fixture",
    )
    (root / "deleted").unlink()
    tracemalloc.start()
    try:
        identity = SOURCE_IDENTITY(root)
        _, peak = tracemalloc.get_traced_memory()
    finally:
        tracemalloc.stop()
    # Golden effective-source digest: filename order, with absent files omitted.
    assert identity["tree_sha256"] == (
        "dfafbc7972ac72daab294e26d93f7d5be9984948f079e0cd74cdfbff3c685b6a"
    )
    assert identity["lockfiles"] == {
        "flake.lock": "ca3d163bab055381827226140568f3bef7eaac187cebd76878e0b63e9e442356"
    }
    assert identity["dirty"]
    assert identity["submodules"] == {}
    assert peak < 4 * 1024 * 1024
