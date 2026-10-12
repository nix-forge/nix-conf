"""Classify only the native Prism watcher regression from QTest XML."""

import argparse
import xml.etree.ElementTree as ET  # ruff: ignore[suspicious-xml-etree-import] - Parse only local native QTest output.
from pathlib import Path
from typing import NoReturn


def _reject(message: str) -> NoReturn:
    raise ValueError(message)


_MAX_XML_BYTES = 1_000_000


def verify(path: Path, mode: str) -> None:
    """Require every native result to match the expected watch capability."""
    content = path.read_bytes()
    if (
        len(content) > _MAX_XML_BYTES
        or b"<!DOCTYPE" in content
        or b"<!ENTITY" in content
    ):
        _reject("Unexpected XML size or declaration")
    root = ET.fromstring(content)  # ruff: ignore[suspicious-xml-element-tree-usage] - Local bounded QTest output; reject entities and doctypes.
    functions = {node.attrib["name"]: node for node in root.findall("TestFunction")}
    expected = {
        "test_1178",
        "test_addFromWatch",
        "test_removeResource",
        "test_enable_disable",
    }
    if not expected.issubset(functions):
        _reject("The full ResourceFolderModel test suite did not execute")
    for name, function in functions.items():
        incidents = function.findall("Incident")
        if not incidents:
            _reject(f"No result for {name}")
        for incident in incidents:
            kind = incident.attrib["type"]
            description = incident.findtext("Description", "")
            _verify_incident(name, mode, kind, description)


def _verify_incident(name: str, mode: str, kind: str, description: str) -> None:
    if name == "test_removeResource" and mode == "unavailable":
        if kind != "fail" or not (
            "Timer has expired. The update never finished." in description
            or (
                "Compared values are not the same" in description
                and "model.size()" in description
            )
        ):
            _reject("The raw case did not fail at a watcher-dependent assertion")
    elif name == "test_removeResource" and mode == "skip":
        if (
            kind != "skip"
            or description != "Native filesystem notifications are unavailable"
        ):
            _reject("The repaired case did not report its exact capability skip")
    elif kind != "pass":
        _reject(f"Unexpected {kind} in {name}: {description}")


def main() -> None:
    """Check the native XML evidence supplied by the proof builder."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["unavailable", "skip", "present"])
    parser.add_argument("xml", type=Path)
    args = parser.parse_args()
    verify(args.xml, args.mode)
    print(f"Verified Prism watch result: {args.mode}")  # ruff: ignore[print] - Report native proof classification to CI.


if __name__ == "__main__":
    main()
