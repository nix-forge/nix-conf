"""Record the ARM recipe arguments and preserve the runner exit status."""

import json
import os
import sys
from pathlib import Path

with Path(os.environ["ARM_TEST_CALLS"]).open("a", encoding="utf-8") as output:
    output.write(json.dumps(sys.argv[1:]) + "\n")
sys.exit(int(os.environ["ARM_TEST_EXIT"]))
