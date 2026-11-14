"""Capture real recipe arguments without exporting, building or deploying."""

import json
import os
import sys
from pathlib import Path

if Path(sys.argv[0]).name == "uname":
    sys.stdout.write(os.environ["FIXTURE_UNAME"] + "\n")
else:
    Path(os.environ["RECIPE_ARGUMENTS"]).write_text(
        json.dumps(sys.argv[1:]), encoding="utf-8"
    )
