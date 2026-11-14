"""Model a renderer fork followed by Chromium's own PID-based scope request."""

from __future__ import annotations

# ruff: file-ignore[suspicious-subprocess-import, unspecified-encoding, subprocess-without-shell-equals-true, start-process-with-partial-path, print] -- This Linux probe deliberately models Chromium's D-Bus scope request and publishes readiness on stdout.
import json
import os
import signal
import subprocess
import sys
from pathlib import Path


def group(pid: int) -> str:
    """Return a process's actual unified cgroup.

    Returns:
        Kernel cgroup path.

    """
    return Path(f"/proc/{pid}/cgroup").read_text().strip().split("::", 1)[1]


if len(sys.argv) > 1 and sys.argv[1] in {"renderer", "backend"}:
    if sys.argv[1] == "backend":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
    print(json.dumps({"pid": os.getpid(), "group": group(os.getpid())}), flush=True)
    if sys.argv[1] == "backend":
        signal.pause()
    else:
        sys.stdin.buffer.read(1)
else:
    with subprocess.Popen(
        [sys.executable, __file__, "renderer"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
    ) as renderer:
        assert renderer.stdout is not None
        observed = json.loads(renderer.stdout.readline())
        subprocess.run(
            [
                "busctl",
                "--user",
                "call",
                "org.freedesktop.systemd1",
                "/org/freedesktop/systemd1",
                "org.freedesktop.systemd1.Manager",
                "StartTransientUnit",
                "ssa(sv)a(sa(sv))",
                f"app-org.chromium.Chromium-{os.getpid()}.scope",
                "fail",
                "1",
                "PIDs",
                "au",
                "1",
                str(os.getpid()),
                "0",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        subprocess.run(
            [
                "systemctl",
                "--user",
                "start",
                f"app-org.chromium.Chromium-{os.getpid()}.scope",
            ],
            check=True,
        )
        own = group(os.getpid())
        assert "/app-codex.slice/" in own, own
        assert "/app-codex.slice/" in observed["group"], observed
        assert own != observed["group"], (own, observed)
        accounting = Path("/sys/fs/cgroup") / own.lstrip("/")
        for name in ("memory.high", "memory.max", "memory.swap.max"):
            assert (accounting / name).read_text().strip() == "max", name
        assert (accounting.parent / "memory.max").read_text().strip() != "max"
        # Spawn only after placement succeeds, so the deliberately failing
        # baseline cannot strand a tool outside the managed launch policy.
        # Normal application exit must reclaim this TERM-ignoring backend.
        backend = subprocess.Popen(
            [sys.executable, __file__, "backend"],
            stdout=subprocess.PIPE,
            text=True,
        )
        assert backend.stdout is not None
        backend_state = json.loads(backend.stdout.readline())
        print(
            json.dumps({
                "main": own,
                "renderer": observed["group"],
                "supervisor": os.getppid(),
                "pid": os.getpid(),
                "rendererPid": observed["pid"],
                "backendPid": backend_state["pid"],
                "args": sys.argv[1:],
                "caller": os.environ.get("CODEX_TEST_CALLER"),
                "umask": next(
                    line.split()[1]
                    for line in Path("/proc/self/status").read_text().splitlines()
                    if line.startswith("Umask:")
                ),
            }),
            flush=True,
        )
        if len(sys.argv) > 1 and sys.argv[1] == "hold":
            signal.pause()
        assert renderer.stdin is not None
        renderer.stdin.write("1")
        renderer.stdin.flush()
        renderer.wait()
