"""Extract the ZIP payload from a CRX browser-extension package."""

import pathlib
import struct
import sys

CRX_MAGIC = b"Cr24"
CRX_VERSION_2 = 2
CRX_VERSION_3 = 3

crx_bytes = pathlib.Path(sys.argv[1]).read_bytes()
if crx_bytes[:4] != CRX_MAGIC:
    error_message = "not a CRX file"
    raise SystemExit(error_message)

version = struct.unpack("<I", crx_bytes[4:8])[0]
if version == CRX_VERSION_2:
    public_key_len, signature_len = struct.unpack("<II", crx_bytes[8:16])
    offset = 16 + public_key_len + signature_len
elif version == CRX_VERSION_3:
    header_len = struct.unpack("<I", crx_bytes[8:12])[0]
    offset = 12 + header_len
else:
    error_message = f"unsupported CRX version: {version}"
    raise SystemExit(error_message)

pathlib.Path(sys.argv[2]).write_bytes(crx_bytes[offset:])
