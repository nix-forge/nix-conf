"""Record cache producer calls without realizing a store or touching a host."""

import json
import os
import sys
from pathlib import Path

with Path(os.environ["CACHE_TEST_RECORD"]).open("a", encoding="utf-8") as record:
    record.write(json.dumps(sys.argv[1:]) + "\n")
sys.stdout.write(
    ("export FIXTURE=1" if sys.argv[1] == "print-dev-env" else "fixture 1234") + "\n"
)
