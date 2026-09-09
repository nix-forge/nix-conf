"""Exercise packaged Python commands against disposable input and output files."""

import io
import json
import os
import pathlib
import struct
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Run the packaged helpers with fixture paths.
import zipfile

root = pathlib.Path.cwd()
archive = io.BytesIO()
with zipfile.ZipFile(archive, "w") as writer:
    writer.writestr(
        "manifest.json", '{"manifest_version":3,"name":"fixture","version":"1"}'
    )
payload = archive.getvalue()
headers = {
    2: struct.pack("<II", 3, 4) + b"keysign",
    3: struct.pack("<I", 4) + b"head",
}
for version, header in headers.items():
    source = root / f"v{version}.crx"
    target = root / f"v{version}.zip"
    source.write_bytes(b"Cr24" + struct.pack("<I", version) + header + payload)
    subprocess.run([os.environ["CRX_PROGRAM"], str(source), str(target)], check=True)  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed executable and argument vector.
    assert target.read_bytes() == payload, version

invalid = [
    b"",
    b"Cr24",
    b"wrong header",
    b"Cr24" + struct.pack("<I", 99),
    b"Cr24" + struct.pack("<I", 2) + b"short",
    b"Cr24" + struct.pack("<III", 2, 9999, 9999),
    b"Cr24" + struct.pack("<I", 3),
    b"Cr24" + struct.pack("<II", 3, 9999) + payload,
    b"Cr24" + struct.pack("<II", 3, 0),
]
for index, data in enumerate(invalid):
    source = root / f"invalid-{index}.crx"
    target = root / f"invalid-{index}.zip"
    source.write_bytes(data)
    target.write_bytes(b"previous output")
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed executable and argument vector.
        [os.environ["CRX_PROGRAM"], str(source), str(target)],
        check=False,
        capture_output=True,
    )
    assert result.returncode != 0, index
    assert target.read_bytes() == b"previous output", index
    assert b"Traceback" not in result.stderr, result.stderr
    assert b"CRX" in result.stderr, result.stderr

preferences = (
    pathlib.Path.home()
    / "Library/Application Support/net.imput.helium/Default/Preferences"
)
preferences.parent.mkdir(parents=True)
preferences.write_text(
    json.dumps({
        "unmanaged": {"keep": [1, 2]},
        "helium": {"browser": {"unmanaged": True}},
    })
)
for iteration in range(2):
    subprocess.run([os.environ["PREFERENCES_PROGRAM"]], check=True)  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed packaged executable.
    settings = json.loads(preferences.read_text())
    assert settings["unmanaged"] == {"keep": [1, 2]}
    assert settings["helium"]["browser"]["unmanaged"] is True
    assert settings["helium"]["nix_default_preferences_version"] == 5
    assert settings["helium"]["browser"]["layout"] == (2 if iteration == 0 else 99)
    settings["helium"]["browser"]["layout"] = 99
    preferences.write_text(json.dumps(settings))
assert not list(preferences.parent.glob("Preferences.nix-*")), (
    "temporary preferences leaked"
)
