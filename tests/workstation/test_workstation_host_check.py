"""A host-identity exception must retain the original hard allocation boundary."""
# Fixed private seams permit checking the privileged refusal path without sudo.

import importlib.util
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from _pytest.monkeypatch import MonkeyPatch

SOURCE = (
    Path(__file__).parents[2]
    / "modules/home/services/workstation-jobs-assets/workstation_host_check.py"
)
SPEC = importlib.util.spec_from_file_location("host_check", SOURCE)
assert SPEC
assert SPEC.loader
host = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(host)
GROUP = "/user.slice/user-1000.slice/user@1000.service/background.slice/background-workload.slice/workstation-task-bulk-123-456.scope"
CONFIG = {"uid": 1000, "minimumMiB": 1024, "maximumMiB": 8192}


@pytest.mark.parametrize(
    ("maximum", "high", "swap", "valid"),
    [
        (4096, 3600, "0", True),
        (8192, 7300, "0", True),
        (16384, 8000, "0", False),
        (4096, 4096, "0", False),
        (4096, 3600, "1024", False),
    ],
)
def test_allocation_is_actual_kernel_state(
    tmp_path: Path, maximum: int, high: int, swap: str, *, valid: bool
) -> None:
    """Oversized, unbounded-pressure and swappable allocations are refused."""
    scope = tmp_path / GROUP.lstrip("/")
    scope.mkdir(parents=True)
    (scope / "memory.max").write_text(str(maximum * host.MIB), encoding="utf-8")
    (scope / "memory.high").write_text(str(high * host.MIB), encoding="utf-8")
    (scope / "memory.swap.max").write_text(swap, encoding="utf-8")
    if valid:
        host.allocation(CONFIG, GROUP, tmp_path)
    else:
        with pytest.raises(ValueError, match="finite qualified"):
            host.allocation(CONFIG, GROUP, tmp_path)


@pytest.mark.parametrize(
    "group",
    [
        "/",
        GROUP.replace("1000", "1001"),
        GROUP.replace("background-workload", "app"),
        GROUP + "/child",
        GROUP.replace("bulk", "feedback"),
    ],
)
def test_other_scopes_cannot_use_privileged_entry(tmp_path: Path, group: str) -> None:
    """Neither other users nor unrelated or feedback scopes qualify."""
    with pytest.raises(ValueError, match="existing workstation"):
        host.allocation(CONFIG, group, tmp_path)


def test_root_cannot_decode_payload(monkeypatch: MonkeyPatch) -> None:
    """Untrusted invocation JSON is never decoded while privileged."""
    monkeypatch.setattr(host.os, "getuid", lambda: 0)
    with pytest.raises(ValueError, match="ordinary host user"):
        host.payload("/not-read", GROUP)
