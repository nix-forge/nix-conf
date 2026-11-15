"""Exercise the Python boundary used by the browser and Electron probes."""

from pathlib import Path

import pytest
import typescript_sources
from typescript_sources import javascript_source


def test_emits_native_javascript_for_a_browser_consumer() -> None:
    """The Python bridge produces executable DOM observer source."""
    source = Path(__file__).with_name("vscode") / "wait-for-dom.ts"
    emitted = javascript_source(source)
    assert "function waitForDOM(" in emitted
    assert "Promise<boolean>" not in emitted
    assert "MutationObserver" in emitted


def test_missing_node_fails_before_attempting_a_probe(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A missing interpreter produces a clear dependency failure."""
    monkeypatch.setattr(typescript_sources.shutil, "which", lambda _name: None)
    with pytest.raises(RuntimeError, match="Node 24"):
        javascript_source(Path("unused.cts"))
