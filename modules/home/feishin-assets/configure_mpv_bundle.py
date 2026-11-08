"""Validate generated artifacts in an isolated build or VM fixture."""

import pathlib
import plistlib
import sys

plist_path = pathlib.Path(sys.argv[1])
if plist_path.exists():
    with plist_path.open("rb") as stream:
        info = plistlib.load(stream)
else:
    info = {"CFBundlePackageType": "APPL", "CFBundleExecutable": "mpv"}
info["CFBundleName"] = "Feishin"
info["CFBundleIdentifier"] = "org.jeffvli.feishin.mpv"
info.pop("CFBundleIconName", None)
info["CFBundleIconFile"] = "icon.icns"
info.pop("CFBundleDocumentTypes", None)
info.pop("CFBundleURLTypes", None)
with plist_path.open("wb") as stream:
    plistlib.dump(info, stream)
