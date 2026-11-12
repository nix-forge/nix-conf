"""Exercise manifest dependency ownership independently of package sources."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING

import pytest
from vscode.check_extension_dependencies import audit_extensions

if TYPE_CHECKING:
    from pathlib import Path


def _manifest(root: Path, folder: str, **fields: object) -> None:
    directory = root / folder
    directory.mkdir(parents=True)
    (directory / "package.json").write_text(json.dumps(fields), encoding="utf-8")


def test_required_dependencies_are_transitive_and_case_insensitive(
    tmp_path: Path,
) -> None:
    """Installing a direct companion does not satisfy its missing dependency."""
    _manifest(
        tmp_path,
        "client",
        publisher="Vendor",
        name="Client",
        extensionDependencies=["vendor.bridge"],
    )
    _manifest(
        tmp_path,
        "bridge",
        publisher="vendor",
        name="Bridge",
        extensionDependencies=["vendor.backend"],
    )
    result = audit_extensions(tmp_path)
    assert result.extension_count == len(list(tmp_path.iterdir()))
    assert result.missing == {"vendor.bridge": ["vendor.backend"]}
    _manifest(tmp_path, "backend", publisher="VENDOR", name="Backend")
    assert audit_extensions(tmp_path).missing == {}


def test_builtin_extensions_satisfy_required_dependencies(tmp_path: Path) -> None:
    """Built-in companions need not be installed a second time by Home Manager."""
    installed, builtin = tmp_path / "installed", tmp_path / "builtin"
    _manifest(
        installed,
        "client",
        publisher="vendor",
        name="client",
        extensionDependencies=["vscode.git"],
    )
    _manifest(builtin, "git", publisher="vscode", name="git")
    assert audit_extensions(installed, builtin).missing == {}


def test_optional_pack_members_are_not_required(tmp_path: Path) -> None:
    """A pack recommendation must not force another semantic provider."""
    _manifest(
        tmp_path,
        "python",
        publisher="ms-python",
        name="python",
        extensionPack=["ms-python.vscode-pylance"],
    )
    assert audit_extensions(tmp_path).missing == {}


def test_duplicate_extension_ids_are_rejected(tmp_path: Path) -> None:
    """Two versions of one extension are not an unambiguous source selection."""
    _manifest(tmp_path, "older", publisher="vendor", name="client")
    _manifest(tmp_path, "newer", publisher="VENDOR", name="Client")
    with pytest.raises(ValueError, match=r"duplicate identifier vendor\.client"):
        audit_extensions(tmp_path)


@pytest.mark.parametrize("dependencies", ["vendor.backend", [None], [""]])
def test_malformed_dependency_fields_are_rejected(
    tmp_path: Path, dependencies: object
) -> None:
    """Malformed requirements must fail rather than being silently skipped."""
    _manifest(
        tmp_path,
        "client",
        publisher="vendor",
        name="client",
        extensionDependencies=dependencies,
    )
    with pytest.raises(ValueError, match="extensionDependencies must be a list"):
        audit_extensions(tmp_path)
