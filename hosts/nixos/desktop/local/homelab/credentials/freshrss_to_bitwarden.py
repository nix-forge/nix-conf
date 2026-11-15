#!/usr/bin/env python3
"""Save the deployed FreshRSS login using the shared homelab vault importer."""

import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "homelab_vault", Path(__file__).with_name("homelab_to_bitwarden.py")
)
if spec is None or spec.loader is None:
    message = "Cannot load the adjacent vault importer"
    raise RuntimeError(message)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
sys.argv.extend(["--only", "FreshRSS"])
helper.cli()
