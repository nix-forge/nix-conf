"""Render bounded feature metadata and real Nix option declarations for the guide."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from pathlib import Path


def cell(value: str) -> str:
    """Escape Markdown table delimiters.

    Returns:
        Text safe for a single Markdown table cell.

    """
    return value.replace("|", "\\|").replace("\n", " ")


def feature_markdown(catalog: dict[str, Any]) -> str:
    """Render the declared supported feature set without inventing verification.

    Returns:
        A Markdown feature table with source and guide links.

    Raises:
        ValueError: The catalog has an unsupported schema or duplicate features.

    """
    if catalog.get("schema") != 1:
        message = "Unsupported feature catalog schema"
        raise ValueError(message)
    names = [feature["name"] for feature in catalog["features"]]
    if len(names) != len(set(names)):
        message = "Feature names must be unique"
        raise ValueError(message)
    lines = [
        "| Feature | Platforms and interface | Dependencies and state | Checks |",
        "| --- | --- | --- | --- |",
    ]
    for feature in catalog["features"]:
        name = cell(feature["name"])
        link = f"[{name}]({feature['guide']})"
        source = f"[source](https://github.com/nix-forge/nix-conf/blob/main/{feature['source']})"
        platforms = ", ".join(feature["platforms"])
        lines.append(
            f"| {link}, {source} | {cell(platforms)}. {cell(feature['interface'])} | {cell(feature['dependencies'])}. {cell(feature['state'])} | {cell(feature['validation'])} |"
        )
    return "\n".join(lines) + "\n"


def option_markdown(options: dict[str, Any]) -> str:
    """Render documented option types and defaults from nixosOptionsDoc JSON.

    Returns:
        A generated Markdown section for every non-internal option.

    """
    lines = [
        "The following types, descriptions and defaults come from the current Nix module declarations. Defaults are not proof that a feature is enabled or deployed.",
        "",
    ]
    for name, option in sorted(options.items()):
        if option.get("internal"):
            continue
        lines.extend([
            f"## `{name}`",
            "",
            "Type:",
            "",
            "```text",
            option["type"],
            "```",
            "",
            option.get("description", ""),
            "",
        ])
        default = option.get("default")
        if default is not None:
            text = (
                default.get("text", str(default))
                if isinstance(default, dict)
                else str(default)
            )
            lines.extend(["Default:", "", "```nix", text, "```", ""])
        for declaration in option.get("declarations", []):
            lines.extend([f"[Declaration]({declaration})", ""])
    return "\n".join(lines)


def insert_reference(staged: Path, catalog: Path, options: Path) -> None:
    """Replace explicit staged-page markers while preserving source Markdown.

    Raises:
        ValueError: A required insertion marker is absent or duplicated.

    """
    for name, marker, rendered in (
        (
            "features.md",
            "<!-- generated-feature-catalog -->",
            feature_markdown(json.loads(catalog.read_text(encoding="utf-8"))),
        ),
        (
            "options.md",
            "<!-- generated-option-reference -->",
            option_markdown(json.loads(options.read_text(encoding="utf-8"))),
        ),
    ):
        page = staged / "guide" / name
        text = page.read_text(encoding="utf-8")
        if text.count(marker) != 1:
            message = f"Expected one reference marker in {name}"
            raise ValueError(message)
        page.chmod(0o644)
        page.write_text(text.replace(marker, rendered), encoding="utf-8")
