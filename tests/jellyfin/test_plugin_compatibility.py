"""Contract tests use the real maintained helper without launching a server."""

from __future__ import annotations

import copy
import os
import sys
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING

import pytest
from jellyfin import plugin_compatibility as check

if TYPE_CHECKING:
    from types import ModuleType


pytestmark = pytest.mark.nix_integration
READ_ONLY_FILE_MODE = 0o444


@pytest.fixture
def helper() -> ModuleType:
    """Return the actual maintained checker module.

    Returns:
        The imported checker with its dataclass module registered.

    """
    default = (
        Path(__file__).resolve().parents[2]
        / "pkgs/pkgs/by-name/je/jellyfin-plugin-intro-skipper/check_jellyfin_plugin.py"
    )
    return check.load_helper(
        Path(os.environ.get("JELLYFIN_INTRO_CHECKER", str(default)))
    )


def _case() -> tuple[dict, list, dict, str]:
    plugins = {
        key: {"version": version, "output": "/nix/store/fixture"}
        for key, version in zip(
            check.IDENTITIES, ("12.0.5.0", "8.0.0.0", "2.4.0.0"), strict=True
        )
    }
    records = [
        {
            "Id": identifier.upper(),
            "Name": name,
            "Version": plugins[key]["version"],
            "Status": "Active",
        }
        for key, (identifier, name, _assembly) in check.IDENTITIES.items()
    ]
    installed = {
        key: Path("fixture-owned/plugins").absolute() / f"{assembly}.dll"
        for key, (_identifier, _name, assembly) in check.IDENTITIES.items()
    }
    log = "\n".join(
        f'Loaded assembly {assembly}, Version={plugins[key]["version"]}, Culture=neutral from "{installed[key]}"'
        for key, (_identifier, _name, assembly) in check.IDENTITIES.items()
    )
    return plugins, records, installed, log


def test_complete_payload_copied_without_changing_package_files(
    helper: ModuleType,
) -> None:
    """The disposable copy retains dependencies and web files without store writes."""
    plugins, _records, _installed, _log = _case()
    with tempfile.TemporaryDirectory() as temporary:
        base = Path(temporary)
        for key, (_identifier, _name, assembly) in check.IDENTITIES.items():
            output = base / assembly
            output.mkdir()
            dll = output / f"{assembly}.dll"
            dll.write_bytes(assembly.encode())
            dll.chmod(READ_ONLY_FILE_MODE)
            plugins[key]["output"] = str(output)
        moon = Path(plugins["Moonfin_nix"]["output"])
        (moon / "SharpCompress.dll").write_bytes(b"dependency")
        (moon / "frontend").mkdir()
        (moon / "frontend/index.html").write_bytes(b"web client")
        installed, port = check.install_plugins(helper, base / "fixture", plugins)
        assert port > 0
        assert (
            installed["Moonfin_nix"].parent / "SharpCompress.dll"
        ).read_bytes() == b"dependency"
        assert (
            installed["Moonfin_nix"].parent / "frontend/index.html"
        ).read_bytes() == b"web client"
        for key, dll in installed.items():
            original = Path(plugins[key]["output"]) / dll.name
            assert dll.read_bytes() == original.read_bytes()
            assert original.stat().st_mode & 0o777 == READ_ONLY_FILE_MODE
            assert dll.stat().st_mode & 0o200


def test_real_helper_registered_for_dataclass_resolution(helper: ModuleType) -> None:
    """Importlib publishes the actual module before executing dataclass declarations."""
    assert sys.modules[helper.__name__] is helper
    assert hasattr(helper.RunningServer, "__dataclass_fields__")


def test_mixed_case_and_compact_guids_match_all_three(helper: ModuleType) -> None:
    """Jellyfin's compact and mixed-case GUID formats identify the same plugins."""
    plugins, records, installed, log = _case()
    records[1]["Id"] = records[1]["Id"].replace("-", "").lower()
    check.validate_plugins(helper, records, plugins)
    check.validate_log(helper, log, installed, plugins)


def test_wrong_version_inactive_missing_or_duplicate_rejected(
    helper: ModuleType,
) -> None:
    """Health alone cannot admit missing, mismatched or inactive plugins."""
    plugins, original, _installed, _log = _case()
    for kind in (
        "version",
        "inactive",
        "missing",
        "duplicate",
        "wrong-id",
        "wrong-name",
    ):
        records = copy.deepcopy(original)
        if kind == "version":
            records[2]["Version"] = "2.3.0.0"
        elif kind == "inactive":
            records[2]["Status"] = "NotSupported"
        elif kind == "missing":
            records.pop(2)
        elif kind == "duplicate":
            records.append(records[2])
        elif kind == "wrong-id":
            records[2]["Id"] = "not-a-guid"
        else:
            records[2]["Name"] = "unexpected"
        with pytest.raises(ValueError, match=r"Expected one|Wrong|not Active"):
            check.validate_plugins(helper, records, plugins)


def test_wrong_dll_path_assembly_version_or_loader_failure_rejected(
    helper: ModuleType,
) -> None:
    """Real paths, assembly versions and service failures remain mandatory."""
    plugins, _records, installed, log = _case()
    for text in (
        log.replace(
            str(installed["Moonfin_nix"]),
            str(Path("unexpected/Moonfin.Server.dll").absolute()),
        ),
        log.replace("Version=2.4.0.0", "Version=2.3.0.0"),
        log + "\nError registering plugin services from Moonfin.Server",
        log + "\nFailed to load assembly x",
        log + "\nError creating Moonfin.Server.MoonfinPlugin",
    ):
        with pytest.raises(
            ValueError, match=r"Missing exact|assembly/type/service|construction"
        ):
            check.validate_log(helper, text, installed, plugins)
