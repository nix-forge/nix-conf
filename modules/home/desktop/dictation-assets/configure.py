"""Reconcile managed Handy preferences without replacing unrelated UI settings."""

import argparse
import json
import os
import tempfile
from pathlib import Path


def configure(data_dir: Path, preferences: dict, model: Path) -> None:
    """Apply explicit preferences atomically and preserve existing model downloads.

    Raises:
        TypeError: Existing application settings are not a JSON object.

    """
    data_dir.mkdir(parents=True, exist_ok=True)
    target = data_dir / "settings_store.json"
    # Invalid JSON must fail before replacing existing preferences.
    document = json.loads(target.read_text()) if target.exists() else {}
    settings = document.setdefault("settings", {})
    if not isinstance(settings, dict):
        message = "Handy settings must be an object"
        raise TypeError(message)
    bindings = preferences.get("bindings", {})
    for key, value in preferences.items():
        if key != "bindings":
            settings[key] = value
    for key, value in bindings.items():
        settings.setdefault("bindings", {}).setdefault(key, {}).update(value)
    models = data_dir / "models"
    models.mkdir(exist_ok=True)
    model_link = models / "parakeet-tdt-0.6b-v2-int8"
    if model_link.is_symlink():
        if model_link.resolve() != model.resolve():
            model_link.unlink()
            model_link.symlink_to(model, target_is_directory=True)
    elif not model_link.exists():
        model_link.symlink_to(model, target_is_directory=True)
    # A previously downloaded model belongs to the user; do not replace it.
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=data_dir, delete=False
    ) as stream:
        temporary = Path(stream.name)
        try:
            json.dump(document, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
            stream.close()
            temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)


def main() -> None:
    """Read policy and application paths from the deployment module."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--preferences", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    args = parser.parse_args()
    configure(args.data_dir, json.loads(args.preferences.read_text()), args.model)


if __name__ == "__main__":
    main()
