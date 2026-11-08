"""Exercise independent readiness writers against one disposable receipt."""

import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("application_readiness", sys.argv[1])
assert spec is not None
assert spec.loader is not None
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
module.write_receipt(
    Path(sys.argv[2]), {"writer": int(sys.argv[3]), "payload": "x" * 10000}
)
