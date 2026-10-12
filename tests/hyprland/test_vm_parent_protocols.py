"""Check the real driver's admission against native wayland-info formatting."""

import ast
import re
from pathlib import Path

import pytest

CAPABILITIES = """interface: 'zwp_linux_dmabuf_v1',                        version:  4, name:  2
interface: 'wl_compositor',                              version:  6, name:  3
interface: 'wl_seat',                                    version:  9, name:  7
interface: 'xdg_wm_base',                                version:  6, name: 10
"""


def _require(capabilities: str) -> None:
    driver = Path(__file__).with_name("subsurface_parent_lifetime_vm.py")
    tree = ast.parse(driver.read_text())
    function = next(
        node
        for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name == "require_parent_protocols"
    )
    namespace = {"re": re}
    exec(  # ruff: ignore[exec-builtin] - Execute only the repository-owned parser AST, without starting the VM driver.
        compile(ast.Module(body=[function], type_ignores=[]), str(driver), "exec"),
        namespace,
    )
    namespace["require_parent_protocols"](capabilities)


def test_padded_native_protocol_versions_are_accepted() -> None:
    """The native tool pads both the interface field and version numbers."""
    _require(CAPABILITIES)


@pytest.mark.parametrize(
    "capabilities",
    [
        CAPABILITIES.replace("version:  6, name: 10", "version:  5, name: 10"),
        CAPABILITIES.replace("zwp_linux_dmabuf_v1", "missing_protocol"),
        CAPABILITIES.replace("version:", "malformed:"),
    ],
)
def test_incompatible_parent_is_rejected(capabilities: str) -> None:
    """Protocol absence, old versions and malformed tool output fail closed."""
    with pytest.raises(AssertionError):
        _require(capabilities)
