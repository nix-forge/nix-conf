"""Serve deterministic wallpaper responses through the curl fixture CLI."""

import json
import shutil
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
args = sys.argv[1:]
config = json.loads((root / "http.json").read_text(encoding="utf-8"))
output = Path(args[args.index("--output") + 1])
query = {}
for index, arg in enumerate(args):
    if arg == "--data-urlencode":
        key, value = args[index + 1].split("=", 1)
        query[key] = value
is_api = "https://commons.wikimedia.org/w/api.php" in args
with (root / "requests.jsonl").open("a", encoding="utf-8") as log:
    log.write(json.dumps({"api": is_api, "query": query, "args": args}) + "\n")
if is_api:
    if query.get("generator") != "categorymembers" or "pageids" in query:
        sys.exit(99)
    key = query.get("gcmtitle", "") + "|" + query.get("gcmcontinue", "")
    response = config["routes"].get(key)
    if response is None:
        sys.exit(98)
    if response == "HTTP failure":
        sys.exit(22)
    output.write_text(json.dumps(response), encoding="utf-8")
else:
    urls = [arg for arg in args if arg.startswith("https://upload.wikimedia.org/")]
    if len(urls) != 1 or urls[0] not in config["media"]:
        sys.exit(97)
    shutil.copyfile(config["media"][urls[0]], output)
