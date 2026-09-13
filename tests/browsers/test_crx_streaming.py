"""Keep CRX extraction bounded while preserving the payload and invalid inputs."""

from __future__ import annotations

import hashlib
import runpy
import struct
import tracemalloc
from pathlib import Path

import pytest

SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "modules/home/helium-browser/scripts/crx-to-zip.py"
)


@pytest.mark.parametrize("version", [2, 3])
def test_large_payload_uses_bounded_memory(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, version: int
) -> None:
    """Copy across many buffer boundaries with an exact payload digest."""
    source, target = tmp_path / "source.crx", tmp_path / "target.zip"
    block = bytes(range(256)) * 4096
    expected = hashlib.sha256()
    header = (
        struct.pack("<III", version, 3, 4) + b"keysign"
        if version == 2  # ruff: ignore[magic-value-comparison] - CRX protocol versions
        else struct.pack("<II", version, 4) + b"head"
    )
    with source.open("wb") as stream:
        stream.write(b"Cr24" + header)
        for _ in range(16):
            stream.write(block)
            expected.update(block)
        stream.write(b"tail")
        expected.update(b"tail")
    monkeypatch.setattr("sys.argv", [str(SCRIPT), str(source), str(target)])
    tracemalloc.start()
    try:
        runpy.run_path(str(SCRIPT), run_name="__main__")
        _, peak = tracemalloc.get_traced_memory()
    finally:
        tracemalloc.stop()
    with target.open("rb") as stream:
        assert hashlib.file_digest(stream, "sha256").digest() == expected.digest()
    # The 16 MiB payload must not become a Python allocation of its own.
    assert peak < 8 * 1024 * 1024


@pytest.mark.parametrize("alias", ["same-path", "hardlink", "symlink"])
def test_output_alias_cannot_truncate_source(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, alias: str
) -> None:
    """Refuse overlapping files before opening the output for streaming."""
    source = tmp_path / "source.crx"
    original = b"Cr24" + struct.pack("<II", 3, 0) + b"payload"
    source.write_bytes(original)
    target = tmp_path / "target.zip"
    if alias == "same-path":
        target = source
    elif alias == "hardlink":
        target.hardlink_to(source)
    else:
        target.symlink_to(source)
    monkeypatch.setattr("sys.argv", [str(SCRIPT), str(source), str(target)])
    with pytest.raises(SystemExit, match="different files"):
        runpy.run_path(str(SCRIPT), run_name="__main__")
    assert source.read_bytes() == original
