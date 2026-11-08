"""Validate generated artifacts in an isolated build or VM fixture."""

import os
import shlex
import xml.etree.ElementTree as ET
from pathlib import Path

root = ET.parse(os.environ["profilePath"]).getroot()
settings = {
    prop.get("{http://openoffice.org/2001/registry}name"): prop.findtext("value")
    for item in root.findall("item")
    for prop in item.findall("prop")
}
assert settings["UseSkia"] == "true"
assert settings["ForceSkia"] == "false"
command = shlex.split(os.environ["languageToolExec"])
properties = Path(command[command.index("--config") + 1]).read_text(encoding="utf-8")
values: dict[str, str] = {}
for line in properties.splitlines():
    if not line or line.startswith("#"):
        continue
    key, value = line.split("=", 1)
    values[key.strip()] = value.strip()

assert values == {
    "cacheSize": "42",
    "cacheTTLSeconds": "7",
    "maxCheckThreads": "3",
    "maxWorkQueueSize": "9",
}, values
