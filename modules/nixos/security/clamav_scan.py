"""Scan regular files through ClamAV's local descriptor protocol.

Retain open files so concurrent cache eviction cannot invalidate a scan. Never
follow links or block while opening special files. Configured blocking workers and
bounded batches preserve daemon backpressure without process polling.
"""

from __future__ import annotations

import argparse
import array
import errno
import os
import selectors
import socket
import stat
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack, suppress
from pathlib import Path
from typing import TYPE_CHECKING, Self

if TYPE_CHECKING:
    from types import TracebackType

BATCH_SIZE = 128
MAX_REPLY_BYTES = 65536


def open_regular(name: str, directory: int | None = None) -> int | None:
    """Retain a regular file without following links.

    Opening or inspecting an otherwise eligible file propagates OSError.

    Returns:
        An owned descriptor, or None for a vanished path or nonregular file.

    """
    try:
        if not stat.S_ISREG(
            os.stat(name, dir_fd=directory, follow_symlinks=False).st_mode
        ):
            return None
        descriptor = os.open(
            name,
            os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK,
            dir_fd=directory,
        )
    except FileNotFoundError:
        return None
    except OSError as error:
        if error.errno == errno.ELOOP:
            return None
        if error.errno in {errno.ENXIO, errno.ENODEV}:
            try:
                current = os.stat(name, dir_fd=directory, follow_symlinks=False)
            except FileNotFoundError:
                current = None
            if current is None or not stat.S_ISREG(current.st_mode):
                return None
        raise
    try:
        if stat.S_ISREG(os.fstat(descriptor).st_mode):
            return descriptor
    except BaseException:
        os.close(descriptor)
        raise
    os.close(descriptor)
    return None


def _receive(connection: socket.socket) -> tuple[int, str]:
    response = bytearray()
    while b"\0" not in response:
        chunk = connection.recv(4096)
        if not chunk:
            return 2, "daemon closed the connection before its reply"
        response.extend(chunk)
        if len(response) > MAX_REPLY_BYTES:
            return 2, "daemon reply exceeds the protocol limit"
    record, _, tail = response.partition(b"\0")
    if tail:
        return 2, "unexpected data after the daemon reply"
    message = record.decode("utf-8", "replace")
    if message.endswith(": OK"):
        return 0, ""
    if message.endswith(" FOUND"):
        return 1, message
    return 2, message or "empty daemon reply"


class _Scanner:
    def __init__(self, endpoint: str, workers: int = 1) -> None:
        self.endpoint = endpoint
        self.result = 0
        self.batch: list[tuple[str, int]] = []
        self.resources = ExitStack()
        self.workers = ThreadPoolExecutor(max_workers=workers)
        self.connections: set[socket.socket] = set()
        self.lock = threading.Lock()
        self.cancelled = threading.Event()
        self.cancel_reader, self.cancel_writer = socket.socketpair()

    def __enter__(self) -> Self:
        return self

    def __exit__(
        self,
        _kind: type[BaseException] | None,
        failure: BaseException | None,
        _traceback: TracebackType | None,
    ) -> None:
        if failure is not None:
            with self.lock:
                self.cancelled.set()
                self.cancel_writer.sendall(b"\0")
                for connection in self.connections:
                    with suppress(OSError):
                        connection.shutdown(socket.SHUT_RDWR)
                    connection.close()
        try:
            self.workers.shutdown(wait=True, cancel_futures=True)
        finally:
            self.resources.close()
            self.cancel_reader.close()
            self.cancel_writer.close()

    def _connect(self, connection: socket.socket) -> None:
        connection.setblocking(False)
        status = connection.connect_ex(self.endpoint)
        if status in {errno.EINPROGRESS, errno.EALREADY, errno.EINTR}:
            with selectors.DefaultSelector() as readiness:
                readiness.register(connection, selectors.EVENT_WRITE)
                readiness.register(self.cancel_reader, selectors.EVENT_READ)
                events = readiness.select()
            if self.cancelled.is_set() or any(
                key.fileobj is self.cancel_reader for key, _ in events
            ):
                raise InterruptedError(errno.ECANCELED, "scan cancelled")
            status = connection.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR)
        if status:
            # A full Unix listener returns EAGAIN without starting a connection.
            # Report backpressure instead of retrying an always-writable socket.
            raise OSError(status, os.strerror(status))
        connection.getpeername()
        connection.setblocking(True)

    def _exchange(self, descriptor: int) -> tuple[int, str]:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            with self.lock:
                if self.cancelled.is_set():
                    return 2, "scan cancelled"
                self.connections.add(connection)
            try:
                self._connect(connection)
                connection.sendall(b"zFILDES\0")
                connection.sendmsg(
                    [b"\0"],
                    [
                        (
                            socket.SOL_SOCKET,
                            socket.SCM_RIGHTS,
                            array.array("i", [descriptor]),
                        )
                    ],
                )
                return _receive(connection)
            finally:
                with self.lock:
                    self.connections.discard(connection)

    def _scan(self, item: tuple[str, int]) -> tuple[int, str]:
        try:
            return self._exchange(item[1])
        except OSError as error:
            return 2, str(error)

    def flush(self) -> None:
        """Finish the retained batch before releasing its descriptors."""
        replies = self.workers.map(self._scan, self.batch)
        for (path, _), (status, message) in zip(self.batch, replies, strict=True):
            self.result = max(self.result, status)
            if message:
                sys.stdout.write(f"{path!r}: {message}\n")
                sys.stdout.flush()
        self.resources.close()
        self.resources = ExitStack()
        self.batch.clear()

    def _error(self, error: OSError) -> None:
        if not isinstance(error, FileNotFoundError):
            self._failure(error)

    def _failure(self, error: OSError) -> None:
        self.result = 2
        sys.stderr.write(f"ERROR: {error}\n")
        sys.stderr.flush()

    def _enqueue(self, path: str, name: str, directory: int | None = None) -> None:
        try:
            descriptor = open_regular(name, directory)
        except OSError as failure:
            self._error(failure)
            return
        if descriptor is not None:
            self.resources.callback(os.close, descriptor)
            self.batch.append((path, descriptor))
        if len(self.batch) == BATCH_SIZE:
            self.flush()

    def scan_root(self, root: str) -> None:
        """Enumerate a selected root without following symlinks."""
        try:
            mode = Path(root).lstat().st_mode
        except OSError as failure:
            self._failure(failure)
            return
        if stat.S_ISREG(mode):
            self._enqueue(root, root)
        elif stat.S_ISDIR(mode):
            for directory, _, filenames, directory_fd in os.fwalk(
                root,
                follow_symlinks=False,
                onerror=self._error,
            ):
                for filename in filenames:
                    self._enqueue(
                        str(Path(directory) / filename), filename, directory_fd
                    )


def scan_roots(endpoint: str, roots: list[str], workers: int = 1) -> int:
    """Scan bounded descriptor batches and retain every genuine failure.

    Returns:
        Zero for clean scans, one for detections, or two for operational errors.

    """
    with _Scanner(endpoint, workers) as scanner:
        for root in roots:
            scanner.scan_root(root)
        scanner.flush()
        return scanner.result


def main() -> int:
    """Parse the local socket and explicitly selected scan roots.

    Returns:
        The aggregate scan exit status.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workers", type=int, default=1)
    parser.add_argument("socket")
    parser.add_argument("roots", nargs="+")
    arguments = parser.parse_args()
    if arguments.workers < 1:
        parser.error("worker count must be positive")
    return scan_roots(arguments.socket, arguments.roots, arguments.workers)


if __name__ == "__main__":
    sys.exit(main())
