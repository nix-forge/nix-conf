"""Record the real scrub supervisor's CLI arguments without touching a disk."""

import json
import sys
from pathlib import Path

Path(__file__).with_suffix(".json").write_text(
    json.dumps(sys.argv[1:]), encoding="utf-8"
)
