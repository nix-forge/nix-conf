"""Wait for the workload's descendants without periodic wakeups."""

import errno
import select
import sys
from pathlib import Path


def wait_until_empty(path: Path) -> None:
    """Block on cgroup v2 notifications until the group is empty or removed.

    Raises:
        OSError: The events file cannot be read for a reason other than removal.
        ValueError: The kernel did not report a valid populated state.

    """
    try:
        events = path.open("rb", buffering=0)
    except FileNotFoundError:
        # The launcher has already exited. systemd may have collected its scope.
        return
    with events:
        poller = select.poll()
        # POLLIN is always ready on this file. Only priority/error events
        # indicate a change; subscribing to reads would create a busy loop.
        poller.register(events, select.POLLPRI | select.POLLERR)
        while True:
            try:
                events.seek(0)
                state = dict(line.split() for line in events.read().splitlines())
            except OSError as error:
                if error.errno == errno.ENODEV:
                    return  # The kernel removed the now-empty cgroup.
                raise
            if state.get(b"populated") == b"0":
                return
            if state.get(b"populated") != b"1":
                message = "cgroup.events has no valid populated state"
                raise ValueError(message)
            # Reading before blocking both handles an already-empty group and
            # acknowledges notifications. A later change makes poll return even
            # if it happens between this read and the blocking call.
            poller.poll()


if __name__ == "__main__":
    try:
        wait_until_empty(Path(sys.argv[1]))
    except (OSError, ValueError) as error:
        sys.stderr.write(f"workstation-task: cannot wait for descendants: {error}\n")
        sys.exit(1)
