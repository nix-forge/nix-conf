"""Blocking readiness and child-exit observers for local Linux test fixtures."""

from __future__ import annotations

from threading import Condition
from time import monotonic
from typing import TYPE_CHECKING

from notification_process import defer_cancellation
from notification_process import wait_child as _wait_child
from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer

if TYPE_CHECKING:
    import subprocess
    from collections.abc import Callable
    from pathlib import Path

    from watchdog.events import FileSystemEvent


class FileChanges(FileSystemEventHandler):
    """Observe persistent fixture state without timer-driven status reads."""

    def __init__(self, directory: Path, *directories: Path) -> None:
        """Watch the fixture directory and all of its descendants."""
        super().__init__()
        self.condition = Condition()
        self.generation = 0
        self.observer = Observer()
        for path in (directory, *directories):
            self.observer.schedule(self, str(path), recursive=True)

    def on_any_event(self, event: FileSystemEvent) -> None:
        """Wake waiters on mutations, excluding reads by their predicates."""
        if event.event_type not in {"created", "modified", "moved", "deleted"}:
            return
        with self.condition:
            self.generation += 1
            self.condition.notify_all()

    def wait(self, predicate: Callable[[], bool], timeout: float = 5) -> None:
        """Subscribe before the snapshot and recheck only after state changes.

        Raises:
            TimeoutError: The predicate remains false at the overall deadline.

        """
        deadline = monotonic() + timeout
        started = False
        try:
            with defer_cancellation():
                self.observer.start()
                started = True
            while True:
                with self.condition:
                    generation = self.generation
                ready = predicate()
                remaining = deadline - monotonic()
                if remaining <= 0:
                    raise TimeoutError
                if ready:
                    return
                with self.condition:
                    if not self.condition.wait_for(
                        lambda generation=generation: self.generation != generation,
                        remaining,
                    ):
                        raise TimeoutError
        finally:
            with defer_cancellation():
                self.observer.stop()
                if started or self.observer.is_alive():
                    self.observer.join()


def wait_file(path: Path, timeout: float = 5) -> None:
    """Wait for a persistent marker, watching its nearest existing ancestor."""
    directory = path.parent
    while not directory.is_dir():
        directory = directory.parent
    FileChanges(directory).wait(path.exists, timeout)


def wait_child(process: subprocess.Popen, timeout: float = 5) -> int:
    """Use native exit notifications with the fixture's five-second default.

    Returns:
        The child process's exit code.

    """
    return _wait_child(process, timeout)
