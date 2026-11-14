"""Emit checked TypeScript as JavaScript for browser and host probes."""

import shutil
from pathlib import Path

from notification_process import run as run_command


def javascript_source(source: Path) -> str:
    """Remove erasable TypeScript syntax for a JavaScript consumer.

    Returns:
        The executable JavaScript source.

    Raises:
        RuntimeError: The declared Node interpreter is unavailable.

    """
    node = shutil.which("node")
    if node is None:
        message = "TypeScript probes require the declared Node 24 runtime"
        raise RuntimeError(message)
    emitter = Path(__file__).with_name("typescript") / "source.mts"
    return run_command(
        [node, str(emitter), str(source)],
        check=True,
        capture_output=True,
        text=True,
        timeout=10,
    ).stdout
