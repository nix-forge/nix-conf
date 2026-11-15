"""Handy preferences remain mutable without losing managed policy."""

import importlib.util
import json
from pathlib import Path

import pytest

SPEC = importlib.util.spec_from_file_location(
    "dictation_configure",
    Path(__file__).parents[2] / "modules/home/desktop/dictation-assets/configure.py",
)
assert SPEC
assert SPEC.loader
configure_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(configure_module)


def test_preserves_unmanaged_preferences_and_refreshes_policy(tmp_path: Path) -> None:
    """Reconcile repeatably without overwriting user choices or exposing preferences."""
    store = tmp_path / "settings_store.json"
    unrelated_value = 42
    private_mode = 0o600
    original = {
        "other": 42,
        "settings": {"selected_microphone": "USB", "model_unload_timeout": "never"},
    }
    store.write_text(json.dumps(original))
    model = tmp_path / "model"
    model.mkdir()
    policy = {"model_unload_timeout": "immediately", "auto_submit": False}
    configure_module.configure(tmp_path, policy, model)
    configure_module.configure(tmp_path, policy, model)
    result = json.loads(store.read_text())
    assert result["other"] == unrelated_value
    assert result["settings"]["selected_microphone"] == "USB"
    assert result["settings"]["model_unload_timeout"] == "immediately"
    assert result["settings"]["auto_submit"] is False
    assert (tmp_path / "models/parakeet-tdt-0.6b-v2-int8").resolve() == model
    assert store.stat().st_mode & 0o777 == private_mode


def test_malformed_settings_are_never_replaced(tmp_path: Path) -> None:
    """Keep damaged user data intact for recovery."""
    store = tmp_path / "settings_store.json"
    store.write_text("broken json")
    with pytest.raises(json.JSONDecodeError):
        configure_module.configure(tmp_path, {}, tmp_path)
    assert store.read_text() == "broken json"


def test_existing_download_is_preserved(tmp_path: Path) -> None:
    """Leave a user-owned downloaded model in place."""
    existing = tmp_path / "models/parakeet-tdt-0.6b-v2-int8"
    existing.mkdir(parents=True)
    (existing / "user-file").write_text("keep")
    configure_module.configure(tmp_path, {}, tmp_path)
    assert (existing / "user-file").read_text() == "keep"
