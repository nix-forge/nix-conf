"""Exercise source-derived reference rendering without invoking a Nix evaluation."""

from __future__ import annotations

import json
import runpy
from pathlib import Path

import pytest

REFERENCE = runpy.run_path(
    str(Path(__file__).resolve().parents[2] / "site/reference.py")
)


def test_option_default_and_type_follow_declarations() -> None:
    """A changed option declaration changes the published reference."""
    options = {
        "services.fixture.enable": {
            "type": "boolean",
            "description": "Enable the fixture.",
            "default": {"text": "false"},
        }
    }
    original = REFERENCE["option_markdown"](options)
    assert "```text\nboolean\n```" in original
    assert "```nix\nfalse\n```" in original
    options["services.fixture.enable"]["default"]["text"] = "true"
    assert "```nix\ntrue\n```" in REFERENCE["option_markdown"](options)


def test_internal_options_are_omitted() -> None:
    """Internal implementation options do not enter the public reference."""
    assert "secretImplementation" not in REFERENCE["option_markdown"]({
        "secretImplementation": {"internal": True, "type": "string"}
    })


def test_duplicate_features_fail_instead_of_hiding_an_entry() -> None:
    """Two names cannot ambiguously identify one feature."""
    with pytest.raises(ValueError, match="unique"):
        REFERENCE["feature_markdown"]({
            "schema": 1,
            "features": [{"name": "duplicate"}, {"name": "duplicate"}],
        })


def test_feature_table_keeps_state_and_check_limits() -> None:
    """The generated feature table preserves explicit support boundaries."""
    feature = {
        "name": "Fixture",
        "guide": "fixture.md",
        "source": "modules/fixture.nix",
        "platforms": ["x86_64-linux"],
        "interface": "fixture.enable",
        "dependencies": "A fixture provider",
        "state": "Data is user-owned",
        "validation": "Evaluation only | no runtime claim",
    }
    text = REFERENCE["feature_markdown"]({"schema": 1, "features": [feature]})
    assert "[Fixture](fixture.md)" in text
    assert "Data is user-owned" in text
    assert "Evaluation only \\| no runtime claim" in text
    assert "modules/fixture.nix" in text


def test_reference_replaces_read_only_nix_source_copy(tmp_path: Path) -> None:
    """Copied store pages can receive generated reference content in staging."""
    guide = tmp_path / "guide"
    guide.mkdir()
    for name, marker in (
        ("features.md", "<!-- generated-feature-catalog -->"),
        ("options.md", "<!-- generated-option-reference -->"),
    ):
        page = guide / name
        page.write_text(marker)
        page.chmod(0o444)
    catalog, options = tmp_path / "catalog.json", tmp_path / "options.json"
    catalog.write_text(json.dumps({"schema": 1, "features": []}))
    options.write_text(
        json.dumps({
            "fixture.enable": {"type": "boolean", "default": {"text": "false"}}
        })
    )
    REFERENCE["insert_reference"](tmp_path, catalog, options)
    assert "fixture.enable" in (guide / "options.md").read_text()
    assert "<!-- generated" not in (guide / "features.md").read_text()


def test_regex_type_is_code_not_a_markdown_link() -> None:
    """Regular-expression option types cannot become broken documentation links."""
    type_text = 'string matching the pattern "[0-9](25[0-5]|2[0-4][0-9])"'
    rendered = REFERENCE["option_markdown"]({"fixture.address": {"type": type_text}})
    assert f"```text\n{type_text}\n```" in rendered
