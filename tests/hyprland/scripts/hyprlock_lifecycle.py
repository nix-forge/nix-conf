"""Check real locker rejection and authentication on a disposable compositor."""

from __future__ import annotations

import argparse
import asyncio
import os
import signal
import tempfile
from contextlib import suppress
from pathlib import Path

from waits import FileChanges


class LoggedProcess:
    """Observe output and child exit through blocking asynchronous notifications."""

    def __init__(self, process: asyncio.subprocess.Process) -> None:
        """Attach one reader and notification condition to this owned child."""
        self.process = process
        self.lines: list[str] = []
        self.condition = asyncio.Condition()
        self.eof = False
        self.reader = asyncio.create_task(self.read())

    async def read(self) -> None:
        """Drain logs without blocking a producer or accumulating unbounded data."""
        assert self.process.stdout is not None
        while line := await self.process.stdout.readline():
            async with self.condition:
                self.lines.append(line.decode(errors="replace"))
                self.lines = self.lines[-300:]
                self.condition.notify_all()
        async with self.condition:
            self.eof = True
            self.condition.notify_all()

    async def wait_text(self, text: str) -> None:
        """Subscribe before checking accumulated output, with a single deadline.

        Raises:
            RuntimeError: The child closes its output before the requested event.

        """
        async with asyncio.timeout(20), self.condition:
            await self.condition.wait_for(
                lambda: self.eof or any(text in line for line in self.lines)
            )
            if not any(text in line for line in self.lines):
                message = f"Process exited before {text}: {''.join(self.lines[-15:])}"
                raise RuntimeError(message)

    async def wait(self) -> int:
        """Wait for native child-exit notification, preserving its exit status.

        Returns:
            The real child exit status.

        """
        async with asyncio.timeout(20):
            result = await self.process.wait()
            await self.reader
        return result

    async def close(self) -> None:
        """Terminate only the disposable process session created by this fixture."""
        with suppress(ProcessLookupError):
            os.killpg(self.process.pid, signal.SIGTERM)
        try:
            await self.wait()
        except TimeoutError:
            with suppress(ProcessLookupError):
                os.killpg(self.process.pid, signal.SIGKILL)
            async with asyncio.timeout(20):
                await self.process.wait()
            self.reader.cancel()
            with suppress(asyncio.CancelledError):
                await self.reader


async def launch(argv: list[str], env: dict[str, str]) -> LoggedProcess:
    """Start an owned process group and collect its bounded output.

    Returns:
        The child with an asynchronous output observer.

    """
    process = await asyncio.create_subprocess_exec(
        *argv,
        env=env,
        stdin=asyncio.subprocess.DEVNULL,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
        start_new_session=True,
    )
    return LoggedProcess(process)


async def wait_socket(path: Path, child: LoggedProcess) -> None:
    """Observe the private socket while continuing to drain its owner's logs.

    Raises:
        RuntimeError: The compositor fails to publish its private socket.

    """
    try:
        await asyncio.to_thread(FileChanges(path.parent).wait, path.exists, timeout=30)
    except TimeoutError as error:
        message = f"No compositor socket {path}: {''.join(child.lines[-30:])}"
        raise RuntimeError(message) from error


async def exercise(args: argparse.Namespace, runtime: Path) -> None:
    """Reject competing lockers and bad credentials without releasing the first lock."""
    children: list[LoggedProcess] = []
    env = os.environ | {
        "XDG_RUNTIME_DIR": str(runtime),
        "WLR_BACKENDS": "headless",
        "WLR_RENDERER": "pixman",
        "LIBGL_ALWAYS_SOFTWARE": "1",
    }
    env.pop("WAYLAND_DISPLAY", None)
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    try:
        cage = await launch([args.cage, "--", args.sleep, "300"], env)
        children.append(cage)
        await wait_socket(runtime / "wayland-0", cage)
        compositor = await launch(
            [args.hyprland, "--i-am-really-stupid", "--config", args.compositor_config],
            env | {"WAYLAND_DISPLAY": "wayland-0", "AQ_BACKEND": "wayland"},
        )
        children.append(compositor)
        await wait_socket(runtime / "wayland-1", compositor)
        locker_env = env | {"WAYLAND_DISPLAY": "wayland-1", "LD_PRELOAD": args.witness}
        argv = [args.locker, "--config", args.config, "--grace", "0", "--verbose"]
        first = await launch(argv, locker_env)
        children.append(first)
        await first.wait_text("onLockLocked called")
        for _ in range(3):
            rejected = await launch(argv, locker_env)
            children.append(rejected)
            await rejected.wait_text("onLockFinished called")
            status = await rejected.wait()
            assert status == 1, (
                f"Rejected locker exited {status}: {''.join(rejected.lines[-15:])}"
            )
            assert "EGL_LIFETIME_WITNESS: armed\n" in rejected.lines
            assert "EGL_LIFETIME_WITNESS: exit thread cleanup\n" in rejected.lines
            deletions = [
                line
                for line in rejected.lines
                if line.startswith("EGL_LIFETIME_WITNESS: delete program ")
            ]
            assert any(not line.rstrip().endswith(" 0") for line in deletions), (
                "Witness did not observe real shader disposal"
            )
            assert first.process.returncode is None, (
                "Competing locker released the original lock"
            )
        keyboard_env = env | {"WAYLAND_DISPLAY": "wayland-1"}
        wrong = await launch(
            [args.wtype, "wrong-fixture-password", "-k", "Return"], keyboard_env
        )
        children.append(wrong)
        assert await wrong.wait() == 0
        await first.wait_text("Authentication failed")
        assert first.process.returncode is None, "Rejected password released the lock"
        correct = await launch(
            [
                args.wtype,
                "-M",
                "ctrl",
                "a",
                "-m",
                "ctrl",
                args.password,
                "-k",
                "Return",
            ],
            keyboard_env,
        )
        children.append(correct)
        assert await correct.wait() == 0
        await first.wait_text("auth: authenticated")
        assert await first.wait() == 0, "Authenticated locker crashed during cleanup"
        replacement = await launch(argv, locker_env)
        children.append(replacement)
        await replacement.wait_text("onLockLocked called")
    finally:
        for child in reversed(children):
            await child.close()


def main() -> None:
    """Run the real protocol and PAM lifecycle check in an isolated guest runtime."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in (
        "cage",
        "sleep",
        "hyprland",
        "locker",
        "wtype",
        "witness",
        "config",
        "compositor-config",
        "password",
    ):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="hyprlock-private-") as directory:
        runtime = Path(directory) / "runtime"
        runtime.mkdir(mode=0o700)
        asyncio.run(exercise(args, runtime))


if __name__ == "__main__":
    main()
