"""Render Soularr credentials only in its private runtime directory."""

import os
import pathlib
import shlex

credentials = pathlib.Path(os.environ["CREDENTIALS_DIRECTORY"])
key = (credentials / "lidarr-api-key").read_text().strip()
lines = (credentials / "slskd-settings").read_text().splitlines()
slskd_key = None
for line in lines:
    name, separator, value = line.partition("=")
    if separator and name.strip() == "SLSKD_API_KEY":
        values = shlex.split(value)
        if len(values) == 1:
            slskd_key = values[0]
if not key or not slskd_key:
    msg = "Missing music integration credential"
    raise RuntimeError(msg)
# INI interpolation is enabled upstream. Reject values that could be
# interpreted as interpolation or additional configuration lines.
if any(c in key + slskd_key for c in "\r\n$%"):
    msg = "Unsupported credential characters"
    raise RuntimeError(msg)
source = pathlib.Path("@settings@")
text = source.read_text(encoding="utf-8")
text = text.replace("@LIDARR_KEY@", key).replace("@SLSKD_KEY@", slskd_key)
target = pathlib.Path(os.environ["RUNTIME_DIRECTORY"]) / "config.ini"
target.write_text(text)
target.chmod(0o600)
