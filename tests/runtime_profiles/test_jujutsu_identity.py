"""Validate protected runtime identity without embedding it in store files."""

from __future__ import annotations

import runpy
from pathlib import Path

import pytest

MODULE = runpy.run_path(
    str(
        Path(__file__).parents[2] / "modules/home/dev/scripts/write_jujutsu_identity.py"
    )
)
LINK = MODULE["_link_identity"]


def test_links_runtime_identity_and_replaces_stale_link(tmp_path: Path) -> None:
    """Keep the provider's runtime path live across generation changes."""
    source = tmp_path / "identity"
    source.write_text(
        '[user]\nname = "Example User"\nemail = "user@example.test"\n', encoding="utf-8"
    )
    source.chmod(0o600)
    destination = tmp_path / "conf.d" / "identity.toml"
    destination.parent.mkdir()
    destination.symlink_to(tmp_path / "missing")
    LINK(destination, source)
    assert destination.is_symlink()
    assert destination.read_bytes() == source.read_bytes()
    assert destination.parent.stat().st_mode & 0o077 == 0


@pytest.mark.parametrize(
    "content",
    [
        '[user]\nname = "Example"\nemail = "user@example.test"\n[aliases]\nbad = "external"',
        '[user]\nname = ""\nemail = "user@example.test"',
        '[user]\nname = 123\nemail = "user@example.test"',
    ],
)
def test_rejects_extra_settings_and_invalid_identity(
    tmp_path: Path, content: str
) -> None:
    """A runtime identity cannot inject unrelated application settings."""
    source = tmp_path / "source"
    source.write_text(content, encoding="utf-8")
    source.chmod(0o600)
    destination = tmp_path / "destination"
    destination.write_text("keep existing identity", encoding="utf-8")
    with pytest.raises(ValueError, match="only a nonempty name and email"):
        LINK(destination, source)
    assert destination.read_text(encoding="utf-8") == "keep existing identity"


def test_rejects_public_runtime_identity(tmp_path: Path) -> None:
    """Readable private identity input is rejected before publishing a link."""
    source = tmp_path / "source"
    source.write_text(
        '[user]\nname="Example"\nemail="user@example.test"', encoding="utf-8"
    )
    source.chmod(0o644)
    with pytest.raises(ValueError, match="protected"):
        LINK(tmp_path / "identity", source)
