"""Extract the ZIP payload from a CRX browser-extension package."""

import pathlib
import shutil
import struct
import sys

CRX_MAGIC = b"Cr24"
CRX_VERSION_2 = 2
CRX_VERSION_3 = 3
VERSION_HEADER_SIZE = 8
V2_HEADER_SIZE = 16
V3_HEADER_SIZE = 12

with pathlib.Path(sys.argv[1]).open("rb") as source:
    header = source.read(V2_HEADER_SIZE)
    if header[:4] != CRX_MAGIC:
        error_message = "not a CRX file"
        raise SystemExit(error_message)

    if len(header) < VERSION_HEADER_SIZE:
        error_message = "truncated CRX version header"
        raise SystemExit(error_message)
    version = struct.unpack("<I", header[4:8])[0]
    if version == CRX_VERSION_2:
        if len(header) < V2_HEADER_SIZE:
            error_message = "truncated CRX v2 header"
            raise SystemExit(error_message)
        public_key_len, signature_len = struct.unpack("<II", header[8:16])
        offset = V2_HEADER_SIZE + public_key_len + signature_len
    elif version == CRX_VERSION_3:
        if len(header) < V3_HEADER_SIZE:
            error_message = "truncated CRX v3 header"
            raise SystemExit(error_message)
        header_len = struct.unpack("<I", header[8:12])[0]
        offset = V3_HEADER_SIZE + header_len
    else:
        error_message = f"unsupported CRX version: {version}"
        raise SystemExit(error_message)

    if offset >= source.seek(0, 2):
        error_message = "CRX header extends beyond its payload"
        raise SystemExit(error_message)

    destination = pathlib.Path(sys.argv[2])
    if destination.exists() and destination.samefile(sys.argv[1]):
        error_message = "CRX input and output must be different files"
        raise SystemExit(error_message)
    source.seek(offset)
    with destination.open("wb") as target:
        shutil.copyfileobj(source, target, length=1024 * 1024)
