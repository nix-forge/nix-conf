"""Enable the model-verified power policy without replacing mutable pairing state."""

import json
import os
import stat
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
metadata = path.stat()
configuration = json.loads(path.read_text(encoding="utf-8"))
televisions = [
    device
    for platform in configuration.get("platforms", [])
    if platform.get("platform") == "SamsungTizen"
    for device in platform.get("devices", [])
    if device.get("name") in {"Samsung S90H - Living Room", "Samsung S90H"}
]
if len(televisions) != 1:
    message = "Expected exactly one configured Samsung S90H for verified power policy"
    raise SystemExit(message)
options = televisions[0].setdefault("options", [])
if "PowerState.Strict" not in options:
    options.append("PowerState.Strict")
    descriptor, temporary = tempfile.mkstemp(prefix=".samsung-power-", dir=path.parent)
    try:
        os.fchmod(descriptor, stat.S_IMODE(metadata.st_mode))
        os.fchown(descriptor, metadata.st_uid, metadata.st_gid)
        with os.fdopen(descriptor, "w") as stream:
            json.dump(configuration, stream, indent=4)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        Path(temporary).replace(path)
    finally:
        if Path(temporary).exists():
            Path(temporary).unlink()
