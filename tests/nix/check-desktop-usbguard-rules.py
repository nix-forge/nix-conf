"""Check that desktop USBGuard allows remain tied to reviewed device identities."""

import base64
import re
import sys
from pathlib import Path

RULE = re.compile(r'^allow id [0-9a-f]{4}:[0-9a-f]{4} hash "([A-Za-z0-9+/=]+)" (.*)$')
FIXED = re.compile(
    r'^parent-hash "([A-Za-z0-9+/=]+)" via-port "[A-Za-z0-9-]+" label "[^"]+"$'
)
MOVABLE = re.compile(
    r'^with-interface equals \{ (?:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2} ?)+\} label "[^"]+"$'
)
SHA256_BYTES = 256 // 8


def digest(value: str) -> None:
    """Require a base64-encoded SHA-256 digest."""
    assert len(base64.b64decode(value, validate=True)) == SHA256_BYTES, (
        "invalid SHA-256 digest"
    )


section = None
seen = set()
counts = {"fixed": 0, "movable": 0}
for line_number, raw in enumerate(
    Path(sys.argv[1]).read_text(encoding="utf-8").splitlines(), 1
):
    line = raw.strip()
    if not line:
        continue
    if line.startswith("#"):
        if line.startswith("# Fixed host controllers"):
            section = "fixed"
        elif line.startswith("# Movable trusted devices"):
            section = "movable"
        continue
    match = RULE.fullmatch(line)
    assert section, f"line {line_number}: allow rule has no policy section"
    assert match, f"line {line_number}: malformed allow rule"
    digest(match[1])
    assert line not in seen, f"line {line_number}: duplicate rule"
    seen.add(line)
    if section == "fixed":
        fixed = FIXED.fullmatch(match[2])
        assert fixed, f"line {line_number}: fixed device lacks parent and port binding"
        digest(fixed[1])
    else:
        assert MOVABLE.fullmatch(match[2]), (
            f"line {line_number}: movable device lacks interface binding"
        )
    counts[section] += 1

assert all(counts.values()), "expected fixed and movable device rules"
