from __future__ import annotations

import time
from collections.abc import Callable


def wait_for(
    fn: Callable[[], bool],
    *,
    name: str,
    timeout_s: int = 180,
    interval_s: float = 2.0,
) -> None:
    deadline = time.monotonic() + timeout_s
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            if fn():
                return
        except Exception as exc:  # noqa: BLE001
            last_error = exc
        time.sleep(interval_s)
    if last_error is not None:
        raise RuntimeError(
            f"timed out waiting for {name}; last error: {last_error}"
        ) from last_error
    raise RuntimeError(f"timed out waiting for {name}")
