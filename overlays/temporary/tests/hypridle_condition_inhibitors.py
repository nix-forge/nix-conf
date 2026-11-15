"""Execute the packaged retry loop with native conditions and D-Bus inhibitors."""

import argparse
import os
import subprocess  # ruff: ignore[suspicious-subprocess-import] - compile and execute a local test
import sys
import tempfile
from pathlib import Path

UNSAFE_INHIBITOR_EXIT = 23

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("fixture", type=Path)
parser.add_argument("--expect-unsafe-inhibitor", action="store_true")
args = parser.parse_args()
source = args.source.read_text(encoding="utf-8")

start = source.index(
    "        for (auto& l : m_sWaylandIdleState.listeners) {",
    source.index("// Check condition_cmd retries"),
)
end = source.index('\n    }\n\n    Debug::log(ERR, "[core] Terminated");', start)
loop = source[start:end]

program = args.fixture.read_text(encoding="utf-8").replace("// @retryLoop@", loop)
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    cpp = root / "retry.cc"
    binary = root / "retry"
    cpp.write_text(program)
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - compiler from the build sandbox
        [os.environ.get("CXX", "c++"), "-std=c++17", str(cpp), "-o", str(binary)],
        check=True,
    )
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - compiler and executable from the build sandbox
        [str(binary)], capture_output=True, text=True, check=False
    )
    if args.expect_unsafe_inhibitor:
        if (
            result.returncode != UNSAFE_INHIBITOR_EXIT
            or result.stdout
            or result.stderr != "Pending condition bypassed an active inhibitor\n"
        ):
            message = "The baseline did not reproduce the precise inhibitor bypass"
            raise RuntimeError(message)
    else:
        result.check_returncode()
sys.stdout.write(
    "Hypridle precise upstream inhibitor bypass reproduced\n"
    if args.expect_unsafe_inhibitor
    else "Hypridle condition/inhibitor regression passed\n"
)
