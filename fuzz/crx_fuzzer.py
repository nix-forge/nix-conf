"""Fuzz CRX header handling and check the extracted payload byte for byte."""

import importlib.util
import pathlib
import struct
import sys
import tempfile

import atheris

MAGIC = b"Cr24"
VERSION_2 = 2
VERSION_3 = 3
V2_HEADER_SIZE = 16
V3_HEADER_SIZE = 12
MAX_INPUT_SIZE = 64 * 1024
METADATA_SIZE = 32

SCRIPT = (
    pathlib.Path(__file__).resolve().parents[1]
    / "modules/home/helium-browser/scripts/crx-to-zip.py"
)
with atheris.instrument_imports():
    spec = importlib.util.spec_from_file_location("crx_to_zip", SCRIPT)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    atheris.instrument_func(module.convert)

directory = tempfile.TemporaryDirectory(prefix="crx-fuzz-")
source = pathlib.Path(directory.name) / "input.crx"
target = pathlib.Path(directory.name) / "output.zip"


def expected_payload(raw: bytes) -> bytes | None:
    """Interpret CRX lengths independently.

    Returns:
        The payload, or None for an invalid header.

    """
    if len(raw) < V3_HEADER_SIZE or raw[:4] != MAGIC:
        return None
    version = int.from_bytes(raw[4:8], "little")
    if version == VERSION_2 and len(raw) >= V2_HEADER_SIZE:
        offset = (
            V2_HEADER_SIZE
            + int.from_bytes(raw[8:12], "little")
            + int.from_bytes(raw[12:16], "little")
        )
    elif version == VERSION_3:
        offset = V3_HEADER_SIZE + int.from_bytes(raw[8:12], "little")
    else:
        return None
    return raw[offset:] if offset < len(raw) else None


def check(raw: bytes) -> None:
    """Compare extraction with the format lengths and preserve the input."""
    if target.exists():
        target.unlink()
    source.write_bytes(raw)
    expected = expected_payload(raw)
    try:
        module.convert(source, target)
    except SystemExit:
        assert expected is None
        assert not target.exists()
    else:
        assert expected is not None
        assert target.read_bytes() == expected
    assert source.read_bytes() == raw


@atheris.instrument_func
def test_one_input(data: bytes) -> None:
    """Try arbitrary bytes and a valid envelope around each input."""
    if len(data) > MAX_INPUT_SIZE:
        return
    check(data)
    version = VERSION_2 if data[:1] < b"\x80" else VERSION_3
    metadata = data[:METADATA_SIZE]
    payload = data[METADATA_SIZE:] or b"\x00"
    if version == VERSION_2:
        wrapped = MAGIC + struct.pack("<III", VERSION_2, len(metadata), 0)
    else:
        wrapped = MAGIC + struct.pack("<II", VERSION_3, len(metadata))
    check(wrapped + metadata + payload)


if __name__ == "__main__":
    atheris.Setup(sys.argv, test_one_input)
    atheris.Fuzz()
