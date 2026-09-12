"""Exercise XML policy through the same CLI used by the libvirt wrappers."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = (
    Path(__file__).parents[2] / "modules/nixos/virtualisation/scripts/libvirt-xml.py"
)
UUID = "70cb4ee0-a076-4ff6-a21c-b26f1a5c93d0"


def run_xml(*arguments: str, xml: str = "") -> subprocess.CompletedProcess[str]:
    """Invoke the parser with disposable text.

    Returns:
        The completed subprocess with captured output and status.

    """
    return subprocess.run(
        [sys.executable, str(SCRIPT), *arguments],
        input=xml,
        text=True,
        capture_output=True,
        check=False,
        timeout=5,
    )


def test_uuid_preservation_is_idempotent(tmp_path: Path) -> None:
    """Preserve XML content and identity regardless of element order or whitespace."""
    definition = tmp_path / "network with spaces.xml"
    definition.write_text(
        '<network><bridge name="virbr-test"/><name>test &amp; dev</name></network>'
    )
    first = run_xml("preserve-uuid", "network", "test & dev", UUID, str(definition))
    assert first.returncode == 0, first.stderr
    assert f"<uuid>{UUID}</uuid>" in first.stdout
    assert '<bridge name="virbr-test"' in first.stdout
    assert "test &amp; dev" in first.stdout
    definition.write_text(first.stdout)
    second = run_xml("preserve-uuid", "network", "test & dev", UUID, str(definition))
    assert second.returncode == 0, second.stderr
    assert second.stdout == first.stdout


@pytest.mark.parametrize(
    ("xml", "existing"),
    [
        ("<network><name>other</name></network>", UUID),
        ("<network><name>test</name></network>", "not-a-uuid"),
        ("<network><name>test</name><uuid>" + "0" * 32 + "</uuid></network>", UUID),
        (
            f"<network><name>test</name><uuid>{UUID}</uuid><uuid>{UUID}</uuid></network>",
            UUID,
        ),
        ("<pool><name>test</name></pool>", UUID),
    ],
)
def test_identity_failure_emits_no_replacement(
    tmp_path: Path, xml: str, existing: str
) -> None:
    """Refuse wrong objects, conflicting UUIDs and ambiguous definitions."""
    definition = tmp_path / "input.xml"
    definition.write_text(xml)
    result = run_xml("preserve-uuid", "network", "test", existing, str(definition))
    assert result.returncode != 0
    assert not result.stdout
    assert definition.read_text() == xml


@pytest.mark.parametrize(
    "xml",
    [
        "<domain>",
        "<pool/>",
        '<!DOCTYPE domain [<!ENTITY name "expansion">]><domain>&name;</domain>',
        "<domain>" + " " * (4 * 1024 * 1024) + "</domain>",
        '<domain><devices><disk device="disk"><target dev="sda"/></disk></devices></domain>',
        '<domain><devices><disk><target dev="sda"/></disk><disk><target dev="sda"/></disk></devices></domain>',
    ],
    ids=[
        "malformed",
        "wrong-root",
        "entities",
        "oversized",
        "missing-source",
        "duplicate-target",
    ],
)
def test_malformed_disk_documents_fail_closed(xml: str) -> None:
    """A parser failure cannot become a misleading successful empty disk lookup."""
    result = run_xml("disk-source", "sda", xml=xml)
    assert result.returncode != 0
    assert not result.stdout


def test_disk_source_preserves_whitespace_and_entities() -> None:
    """Read the full path instead of the fourth display column."""
    result = run_xml(
        "disk-source",
        "sda",
        xml='<domain><devices><disk device="disk"><source file="/VM disks/a &amp; b.qcow2"/>'
        '<target dev="sda"/></disk></devices></domain>',
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout == "/VM disks/a & b.qcow2\n"


def installer_xml() -> str:
    """Construct independently specified installation devices.

    Returns:
        XML with one writable disk and the required read-only media.

    """
    return (
        '<domain><devices><disk device="disk"><source file="/VM disks/system.qcow2"/>'
        '<target dev="sda" bus="sata"/><serial>system</serial></disk>'
        '<disk device="disk"><source file="/VM disks/prime.qcow2"/>'
        '<target dev="sdb"/><readonly/></disk>'
        + "".join(
            f'<disk device="cdrom"><target dev="{target}"/><readonly/></disk>'
            for target in ("sdc", "sdd", "sde")
        )
        + "</devices></domain>"
    )


@pytest.mark.parametrize(
    ("old", "new"),
    [
        ("system.qcow2", "wrong.qcow2"),
        ("<serial>system</serial>", "<serial>wrong</serial>"),
        ('bus="sata"', 'bus="virtio"'),
        ("prime.qcow2", "wrong.qcow2"),
        ('<target dev="sde"/><readonly/>', '<target dev="sde"/>'),
        ('<target dev="sde"/>', '<target dev="sda"/>'),
    ],
)
def test_installer_policy_rejects_unsafe_topology(
    tmp_path: Path, old: str, new: str
) -> None:
    """Reject changes to target identity or media write protection."""
    definition = tmp_path / "installer.xml"
    definition.write_text(installer_xml())
    arguments = (
        "installer-topology",
        str(definition),
        "/VM disks/system.qcow2",
        "system",
        "/VM disks/prime.qcow2",
    )
    valid = run_xml(*arguments)
    assert valid.returncode == 0, valid.stderr
    definition.write_text(installer_xml().replace(old, new))
    invalid = run_xml(*arguments)
    assert invalid.returncode != 0
    assert not invalid.stdout


def test_pool_path_is_not_trimmed() -> None:
    """Read exact paths while ignoring unrelated pool fields."""
    result = run_xml(
        "pool-path", xml="<pool><target><path>/VM disks/ data </path></target></pool>"
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout == "/VM disks/ data \n"
