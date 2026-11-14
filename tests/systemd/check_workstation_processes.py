"""Exercise scheduler lifecycle contracts using FIFO and process notifications."""

from __future__ import annotations

import contextlib
import os
import select
import signal
import subprocess
import sys
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Generator, Sequence

HERE = Path(__file__).resolve().parent
CHILD = HERE / "workstation_task_child.py"
SHELL_CHILD = HERE / "workstation-task-child.sh"
DEADLINE = 10.0


@contextlib.contextmanager
def fifo(path: Path) -> Generator[int]:
    """Register readiness before a producer can publish or exit.

    Yields:
        An open FIFO descriptor retained until the scenario finishes.

    """
    os.mkfifo(path)
    fd = os.open(path, os.O_RDWR | os.O_NONBLOCK | os.O_CLOEXEC)
    try:
        yield fd
    finally:
        os.close(fd)


def reap(job: subprocess.Popen, timeout: float = DEADLINE) -> int:
    """Block on process exit, then collect its status without timed polling.

    Returns:
        The reaped process exit status.

    """
    fd = os.pidfd_open(job.pid)
    try:
        assert select.select([fd], [], [], timeout)[0], "process deadline expired"
        return job.wait()
    finally:
        os.close(fd)


@contextlib.contextmanager
def process(command: Sequence[str]) -> Generator[subprocess.Popen]:
    """Own a child and bound cleanup, including failed assertions.

    Yields:
        The supervised process, which is reaped on normal exit or cancellation.

    """
    job = subprocess.Popen(command)
    try:
        yield job
    finally:
        if job.poll() is None:
            job.terminate()
            try:
                reap(job)
            except AssertionError:
                job.kill()
                reap(job)


def ready(fd: int, job: subprocess.Popen) -> int:
    """Wait for readiness or fail immediately if the launcher exits first.

    Returns:
        The PID published by the ready fixture.

    """
    pidfd = os.pidfd_open(job.pid)
    try:
        events = select.select([fd, pidfd], [], [], DEADLINE)[0]
        assert fd in events, "workload exited or missed its readiness deadline"
        return int(os.read(fd, 256).decode().strip())
    finally:
        os.close(pidfd)


def release(path: Path) -> None:
    """Release an already waiting fixture without depending on FIFO open order."""
    fd = os.open(path, os.O_RDWR | os.O_CLOEXEC)
    try:
        os.write(fd, b"continue\n")
    finally:
        os.close(fd)


def alive(pid: int) -> bool:
    """Accept a reaped process or a zombie waiting for its parent to reap it.

    Returns:
        Whether the process exists and is still running.

    """
    status = Path("/proc") / str(pid) / "stat"
    try:
        return status.read_text(encoding="utf-8").split()[2] != "Z"
    except FileNotFoundError:
        return False


def run(command: Sequence[str]) -> int:
    """Execute a bounded command through the same exit-notification path.

    Returns:
        The command exit status.

    """
    with process(command) as job:
        return reap(job)


def check(runner: str, directory: str, stack: contextlib.ExitStack) -> None:
    """Check queueing, cancellation, descendants, and launch errors."""
    root = Path(directory)
    command = [runner, sys.executable, str(CHILD)]
    queue_ready = root / "queue-ready"
    queue_release = root / "queue-release"
    stack.enter_context(fifo(queue_release))
    with (
        fifo(queue_ready) as fd,
        process([
            runner,
            "bash",
            str(SHELL_CHILD),
            "queue-first",
            str(root),
            str(queue_ready),
            str(queue_release),
        ]) as first,
    ):
        ready(fd, first)
        with process([
            runner,
            "bash",
            str(SHELL_CHILD),
            "queue-second",
            str(root),
        ]) as second:
            select.select([], [], [], 0.2)
            assert (root / "order").read_text().strip() == "first-start"
            release(queue_release)
            assert reap(first) == 0
            assert reap(second) == 0
    assert (root / "order").read_text().splitlines() == [
        "first-start",
        "first-end",
        "second",
    ]
    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        marker = root / f"signal-{sig}"
        unblock = root / f"release-{sig}"
        stack.enter_context(fifo(unblock))
        with (
            fifo(marker) as fd,
            process([*command, "hold", str(marker), str(unblock)]) as job,
        ):
            pid = ready(fd, job)
            job.send_signal(sig)
            assert reap(job) == 128 + sig
            assert not alive(pid), "cancelled workload survived"

    holder_ready = root / "holder-ready"
    holder_release = root / "holder-release"
    stack.enter_context(fifo(holder_release))
    queued_marker = root / "queued-must-not-start"
    with (
        fifo(holder_ready) as fd,
        process([*command, "hold", str(holder_ready), str(holder_release)]) as holder,
    ):
        ready(fd, holder)
        with process([runner, "touch", str(queued_marker)]) as queued:
            # Observe a quiet interval once; no state is polled during it.
            assert not select.select([], [], [], 0.2)[0]
            queued.terminate()
            assert reap(queued) == 128 + signal.SIGTERM
            assert not queued_marker.exists()
        holder.terminate()
        reap(holder)

    order = root / "descendant-order"
    trace = root / "descendant-execs"
    assert (
        run([
            "strace",
            "-f",
            "-yy",
            "-e",
            "trace=execve,poll",
            "-o",
            str(trace),
            *command,
            "parent",
            str(order),
            "0",
        ])
        == 0
    )
    assert run([*command, "append-second", str(order)]) == 0
    assert order.read_text().splitlines() == [
        "parent-finished",
        "child-finished",
        "second-started",
    ]
    lines = trace.read_text().splitlines()
    probes = [line for line in lines if '"is-active"' in line and line.endswith("= 0")]
    assert len(probes) <= 1, "descendant wait repeatedly queried systemd"
    waits = [line for line in lines if "poll(" in line and "cgroup.events" in line]
    assert len(waits) < 10, "descendant wait spun on cgroup events"
    for status in (0, 23):
        assert run([*command, "parent", str(order), str(status)]) == status
        assert order.read_text().splitlines() == ["parent-finished", "child-finished"]

    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        parent_ready = root / f"departed-parent-{sig}"
        child_ready = root / f"remaining-child-{sig}"
        parent_continue = root / f"parent-continue-{sig}"
        child_release = root / f"child-release-{sig}"
        stack.enter_context(fifo(parent_continue))
        stack.enter_context(fifo(child_release))
        with (
            fifo(parent_ready) as parent_fd,
            fifo(child_ready) as child_fd,
            process([
                *command,
                "departing-parent",
                str(parent_ready),
                str(child_ready),
                str(parent_continue),
                str(child_release),
            ]) as job,
        ):
            parent_pid = ready(parent_fd, job)
            parent_pidfd = os.pidfd_open(parent_pid)
            try:
                release(parent_continue)
                child_pid = ready(child_fd, job)
                assert select.select([parent_pidfd], [], [], DEADLINE)[0]
            finally:
                os.close(parent_pidfd)
            runner_pidfd = os.pidfd_open(job.pid)
            try:
                assert not select.select([runner_pidfd], [], [], 0)[0], (
                    "queue released early"
                )
            finally:
                os.close(runner_pidfd)
            job.send_signal(sig)
            assert reap(job) == 128 + sig
            assert not alive(child_pid), "descendant survived cancellation"

    assert run([runner, "/nonexistent/workstation-test-command"]) != 0
    assert run([runner, "true"]) == 0


if __name__ == "__main__":
    with contextlib.ExitStack() as stack:
        check(sys.argv[1], sys.argv[2], stack)
