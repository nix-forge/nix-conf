"""Report the workspace environment and working directory."""

# ruff: file-ignore[print] -- Provides the ordered test output protocol.
import os
from pathlib import Path

print(os.environ["WORKSPACE_STATE_DIR"])
print(os.environ["WORKSPACE_SOURCE_DIR"])
print(Path.cwd())
