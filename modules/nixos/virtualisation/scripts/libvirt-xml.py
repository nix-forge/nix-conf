"""Read managed libvirt XML without relying on display columns or regex edits."""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import TextIO
from uuid import UUID

MAX_XML_BYTES = 4 * 1024 * 1024
INSTALLER_OPTICAL_DISKS = 3


class PolicyError(ValueError):
    """A document violates the managed VM contract."""


def parse_document(stream: TextIO, kind: str) -> ET.Element:
    """Read bounded UTF-8 XML.

    Returns:
        The validated root element.

    Raises:
        PolicyError: The document is oversized, declares entities or has the wrong root.

    """
    text = stream.read(MAX_XML_BYTES + 1)
    if len(text.encode("utf-8")) > MAX_XML_BYTES:
        raise PolicyError("libvirt XML exceeds the size limit")
    # Generated libvirt documents need neither DTDs nor entity declarations.
    # Reject these before ElementTree can expand internal entity references.
    if re.search(r"<!\s*(?:DOCTYPE|ENTITY)\b", text, re.IGNORECASE):
        raise PolicyError("libvirt XML must not contain DTD or entity declarations")
    root = ET.fromstring(text)
    if root.tag != kind:
        raise PolicyError(f"expected a {kind} document")
    return root


def child(element: ET.Element, name: str) -> ET.Element | None:
    """Read an unambiguous child.

    Returns:
        The child, or None when absent.

    Raises:
        PolicyError: The document repeats a single-valued element.

    """
    matches = element.findall(name)
    if len(matches) > 1:
        raise PolicyError(f"duplicate {name} element")
    return matches[0] if matches else None


def attribute(element: ET.Element, name: str, key: str) -> str:
    """Read an optional attribute from an unambiguous child.

    Returns:
        The attribute value, or an empty string when absent.

    """
    found = child(element, name)
    return found.get(key, "") if found is not None else ""


def text_value(element: ET.Element, name: str) -> str:
    """Read optional element text without trimming filesystem path bytes.

    Returns:
        The element text, or an empty string when absent.

    """
    found = child(element, name)
    return (found.text or "") if found is not None else ""


def preserve_uuid(root: ET.Element, name: str, value: str) -> None:
    """Preserve an existing object's UUID.

    Raises:
        PolicyError: The name or UUID is invalid or conflicts with the existing object.

    """
    if text_value(root, "name") != name:
        raise PolicyError("definition names a different libvirt object")
    if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", value):
        raise PolicyError("existing object returned an invalid UUID")
    expected = UUID(value)
    existing = child(root, "uuid")
    if existing is not None:
        try:
            actual = UUID(existing.text or "")
        except ValueError as error:
            raise PolicyError("definition contains an invalid UUID") from error
        if actual != expected:
            raise PolicyError("refusing to replace an existing object's UUID")
    else:
        existing = ET.SubElement(root, "uuid")
    existing.text = str(expected)


@dataclass(frozen=True)
class Disk:
    """The disk properties used by managed installation policy."""

    device: str
    source: str
    target: str
    bus: str
    serial: str
    readonly: bool


def disks(root: ET.Element) -> list[Disk]:
    """Decode disk records.

    Returns:
        The domain disks in document order.

    Raises:
        PolicyError: Devices or targets are absent or ambiguous.

    """
    devices = child(root, "devices")
    if devices is None:
        raise PolicyError("domain has no devices")
    result = [
        Disk(
            device=node.get("device", ""),
            source=attribute(node, "source", "file"),
            target=attribute(node, "target", "dev"),
            bus=attribute(node, "target", "bus"),
            serial=text_value(node, "serial"),
            readonly=child(node, "readonly") is not None,
        )
        for node in devices.findall("disk")
    ]
    targets = [disk.target for disk in result]
    if any(not target for target in targets) or len(set(targets)) != len(targets):
        raise PolicyError("disk targets must be present and unique")
    return result


def disk_source(root: ET.Element, target: str) -> str:
    """Read a file-backed disk source exactly.

    Returns:
        The full path, or an empty string if the target is absent.

    Raises:
        PolicyError: The managed target has no file source.

    """
    for disk in disks(root):
        if disk.device == "disk" and disk.target == target:
            if not disk.source:
                raise PolicyError("managed system disk must have a file source")
            return disk.source
    return ""


def validate_installer(root: ET.Element, system: str, serial: str, prime: str) -> None:
    """Check the installer's writable disk and read-only helper/media topology.

    Raises:
        PolicyError: The devices do not match the managed installation contract.

    """
    records = disks(root)
    writable = [disk for disk in records if disk.device == "disk" and not disk.readonly]
    helpers = [disk for disk in records if disk.device == "disk" and disk.readonly]
    optical = [disk for disk in records if disk.device == "cdrom"]
    if len(writable) != 1:
        raise PolicyError("installer must expose exactly one writable disk")
    disk = writable[0]
    if (disk.source, disk.serial, disk.target, disk.bus) != (
        system,
        serial,
        "sda",
        "sata",
    ):
        raise PolicyError(
            "installer writable disk does not match the managed SATA disk"
        )
    if len(helpers) != 1 or helpers[0].source != prime:
        raise PolicyError("installer must expose the read-only driver-prime disk")
    if len(optical) != INSTALLER_OPTICAL_DISKS or any(
        not disk.readonly for disk in optical
    ):
        raise PolicyError("installer must expose exactly three read-only optical media")


def execute(args: argparse.Namespace) -> str:
    """Read and validate a document for a CLI operation.

    Returns:
        The serialized result, or empty text for successful validation.

    Raises:
        PolicyError: A required pool path is absent.

    """
    kind = getattr(args, "kind", "pool" if args.command == "pool-path" else "domain")
    if hasattr(args, "file"):
        with args.file.open(encoding="utf-8-sig") as stream:
            root = parse_document(stream, kind)
    else:
        root = parse_document(sys.stdin, kind)
    if args.command == "preserve-uuid":
        preserve_uuid(root, args.name, args.uuid)
        return ET.tostring(root, encoding="unicode")
    if args.command == "disk-source":
        return disk_source(root, args.target)
    if args.command == "pool-path":
        target = child(root, "target")
        if target is None or not text_value(target, "path"):
            raise PolicyError("pool has no target path")
        return text_value(target, "path")
    validate_installer(root, args.system_disk, args.serial, args.prime_disk)
    return ""


def main() -> int:
    """Run one XML operation without invoking commands or mutating live state.

    Returns:
        Zero on success, one when input or policy validation fails.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    identity = commands.add_parser("preserve-uuid")
    identity.add_argument("kind", choices=("network", "pool"))
    identity.add_argument("name")
    identity.add_argument("uuid")
    identity.add_argument("file", type=Path)
    source = commands.add_parser("disk-source")
    source.add_argument("target")
    commands.add_parser("pool-path")
    installer = commands.add_parser("installer-topology")
    installer.add_argument("file", type=Path)
    installer.add_argument("system_disk")
    installer.add_argument("serial")
    installer.add_argument("prime_disk")
    args = parser.parse_args()
    try:
        result = execute(args)
    except (OSError, ValueError, ET.ParseError) as error:
        sys.stderr.write(f"libvirt XML: {error}\n")
        return 1
    if result:
        sys.stdout.write(result + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
