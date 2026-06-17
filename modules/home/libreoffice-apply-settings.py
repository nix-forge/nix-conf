"""Apply Home Manager-owned settings to a mutable LibreOffice profile."""

from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ET  # noqa: S405
from pathlib import Path
from typing import Final, TypedDict

OOR: Final = "http://openoffice.org/2001/registry"
XS: Final = "http://www.w3.org/2001/XMLSchema"
XSI: Final = "http://www.w3.org/2001/XMLSchema-instance"
NAME: Final = f"{{{OOR}}}name"
OP: Final = f"{{{OOR}}}op"
PATH: Final = f"{{{OOR}}}path"


class Setting(TypedDict):
    """One LibreOffice registry property managed by Home Manager."""

    path: str
    name: str
    value: str


def load_tree(profile: Path) -> ET.ElementTree[ET.Element]:
    """Load an existing profile or create an empty LibreOffice registry.

    Returns:
        The parsed or newly created registry tree.

    """
    if profile.exists():
        return ET.parse(profile)  # noqa: S314

    root = ET.Element(
        f"{{{OOR}}}items",
        {
            "xmlns:xs": XS,
            "xmlns:xsi": XSI,
        },
    )
    return ET.ElementTree(root)


def load_settings(settings_path: Path) -> list[Setting]:
    """Load the generated list of managed settings.

    Returns:
        The ordered settings to apply.

    """
    with settings_path.open(encoding="utf-8") as settings_file:
        return json.load(settings_file)


def apply_setting(root: ET.Element, setting: Setting) -> bool:
    """Upsert one setting and remove duplicate copies of the same property.

    Returns:
        Whether the registry tree changed.

    """
    matches: list[ET.Element] = []
    for item in root.findall("item"):
        if item.get(PATH) != setting["path"]:
            continue
        matches.extend(
            prop for prop in item.findall("prop") if prop.get(NAME) == setting["name"]
        )

    changed = False
    if matches:
        prop = matches[0]
    else:
        item = ET.SubElement(root, "item", {PATH: setting["path"]})
        prop = ET.SubElement(item, "prop", {NAME: setting["name"], OP: "fuse"})
        changed = True

    value = prop.find("value")
    if value is None:
        value = ET.SubElement(prop, "value")
        changed = True
    if value.text != setting["value"]:
        value.text = setting["value"]
        changed = True

    for duplicate in matches[1:]:
        for item in root.findall("item"):
            if duplicate not in list(item):
                continue
            item.remove(duplicate)
            if not list(item):
                root.remove(item)
            changed = True
            break

    return changed


def write_tree(tree: ET.ElementTree[ET.Element], profile: Path) -> None:
    """Back up the current profile and atomically write the updated tree."""
    if profile.exists():
        shutil.copy2(profile, profile.with_name(f"{profile.name}.home-manager-backup"))

    file_descriptor, temporary_name = tempfile.mkstemp(
        prefix=".registrymodifications.",
        suffix=".xcu",
        dir=profile.parent,
    )
    os.close(file_descriptor)
    temporary = Path(temporary_name)
    try:
        tree.write(temporary, encoding="UTF-8", xml_declaration=True)
        temporary.chmod(0o600)
        temporary.replace(profile)
    finally:
        temporary.unlink(missing_ok=True)


def main() -> None:
    """Apply all managed settings when the profile differs."""
    profile = Path(sys.argv[1])
    settings_path = Path(sys.argv[2])
    profile.parent.mkdir(mode=0o700, parents=True, exist_ok=True)

    ET.register_namespace("oor", OOR)
    ET.register_namespace("xs", XS)
    ET.register_namespace("xsi", XSI)

    tree = load_tree(profile)
    changed = False
    for setting in load_settings(settings_path):
        changed = apply_setting(tree.getroot(), setting) or changed
    if changed:
        write_tree(tree, profile)


if __name__ == "__main__":
    main()
