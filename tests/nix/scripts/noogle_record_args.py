"""Record a fixture command invocation for the NixOS test driver."""

import json
import sys
from pathlib import Path

with Path(sys.argv[1]).open("w", encoding="utf-8") as output:
    json.dump(sys.argv[2:], output)
