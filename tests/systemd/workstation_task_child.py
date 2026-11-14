"""Workload fixtures for the native scheduler contract test."""

import os
import subprocess
import sys
import time
from pathlib import Path


def notify(destination: str) -> None:
    """Publish a PID after the fixture is ready to accept cancellation."""
    Path(destination).write_text(f"{os.getpid()}\n", encoding="utf-8")


def main() -> None:
    """Run one explicit workload scenario in the isolated scope.

    Raises:
        ValueError: The caller selected an unknown fixture mode.

    """
    mode, *arguments = sys.argv[1:]
    if mode == "hold":
        ready, release = arguments
        notify(ready)
        with Path(release).open(encoding="utf-8") as pipe:
            pipe.readline()
    elif mode == "delayed-child":
        order = Path(arguments[0])
        # A delay is the test stimulus: the parent must retain its queue slot.
        time.sleep(0.5)
        with order.open("a", encoding="utf-8") as output:
            output.write("child-finished\n")
    elif mode == "parent":
        order, status = arguments
        Path(order).write_text("parent-finished\n", encoding="utf-8")
        subprocess.Popen(
            [sys.executable, __file__, "delayed-child", order],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        sys.exit(int(status))
    elif mode == "departing-parent":
        parent_ready, child_ready, parent_continue, release = arguments
        notify(parent_ready)
        with Path(parent_continue).open(encoding="utf-8") as pipe:
            pipe.readline()
        subprocess.Popen(
            [sys.executable, __file__, "hold", child_ready, release],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    elif mode == "append-second":
        with Path(arguments[0]).open("a", encoding="utf-8") as output:
            output.write("second-started\n")
    elif mode == "oom-parent":
        ready, release, survivor = arguments
        group = Path("/sys/fs/cgroup") / Path("/proc/self/cgroup").read_text(
            encoding="utf-8"
        ).strip().split("::", 1)[1].lstrip("/")
        assert (group / "memory.max").read_text().strip() == str(96 * 1024 * 1024)
        assert (group / "memory.oom.group").read_text().strip() == "1"
        notify(ready)
        with Path(release).open(encoding="utf-8") as pipe:
            pipe.readline()
        subprocess.run([sys.executable, __file__, "allocate"], check=False)
        Path(survivor).touch()
    elif mode == "allocate":
        allocation = bytearray(128 * 1024 * 1024)
        assert len(allocation) == 128 * 1024 * 1024
    else:
        message = f"Unknown fixture mode: {mode}"
        raise ValueError(message)


if __name__ == "__main__":
    main()
