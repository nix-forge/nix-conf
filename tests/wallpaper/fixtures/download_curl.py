"""Serve deterministic wallpaper responses through the curl fixture CLI."""

import json
import shutil
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
url = sys.argv[-1]
with (root / "requests").open("a", encoding="utf-8") as log:
    log.write(url + "\n")
responses = json.loads((root / "http.json").read_text(encoding="utf-8"))
if url not in responses or responses[url] == "FAIL":
    sys.exit(22)
out = Path(sys.argv[sys.argv.index("--output") + 1])
response = responses[url]
if response == "IMAGE":
    shutil.copyfile(root / "original.jpg", out)
elif isinstance(response, dict):
    out.write_text(json.dumps(response), encoding="utf-8")
else:
    out.write_text(response, encoding="utf-8")
