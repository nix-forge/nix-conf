#!/usr/bin/env python3
"""Check that a child OOM does not stop either ChatGPT application scope.

Requires a systemd user manager and cgroup v2. Allocations are confined to a
96 MiB scope with no swap; this never attempts to exhaust system memory.
"""

from __future__ import annotations

import os
import select
import shutil
import signal
import subprocess  # ruff: ignore[suspicious-subprocess-import] - This regression supervises a confined child and its systemd scope.
import sys
import tempfile
import time
from pathlib import Path

_MEMORY_LIMIT = 96 * 1024 * 1024
_SUCCESS_MESSAGE = "PASS: child OOM recorded; application parent survived\n"


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def _workload() -> None:
    cgroup = (
        Path("/proc/self/cgroup").read_text(encoding="utf-8").strip().split("::", 1)[1]
    )
    directory = Path("/sys/fs/cgroup") / cgroup.lstrip("/")
    _require(
        directory.joinpath("memory.max").read_text(encoding="utf-8").strip()
        == str(_MEMORY_LIMIT),
        "The test scope must enforce the 96 MiB memory limit",
    )
    _require(
        directory.joinpath("memory.swap.max").read_text(encoding="utf-8").strip()
        == "0",
        "The test scope must disable swap",
    )
    with subprocess.Popen([
        sys.executable,
        str(Path(__file__).with_name("chatgpt_oom_child.py")),
    ]) as child:
        pidfd = os.pidfd_open(child.pid)
        try:
            _require(
                bool(select.select([pidfd], [], [], 10)[0]), "OOM deadline expired"
            )
            child.wait()
        finally:
            os.close(pidfd)
            if child.poll() is None:
                child.kill()
                child.wait()
    events = dict(
        line.split()
        for line in directory
        .joinpath("memory.events")
        .read_text(encoding="utf-8")
        .splitlines()
    )
    _require(
        child.returncode == -signal.SIGKILL,
        f"Expected SIGKILL, received {child.returncode}",
    )
    _require(int(events["oom_kill"]) >= 1, f"Missing OOM kill event: {events}")
    # Let the manager act on the OOM notification before declaring survival.
    time.sleep(2)
    sys.stdout.write(_SUCCESS_MESSAGE)
    sys.stdout.flush()


def _run(arguments: list[str], timeout: int = 20) -> subprocess.CompletedProcess[str]:
    # Captured output is bounded; a pidfd deadline replaces timed wait polling.
    with (
        tempfile.TemporaryFile(mode="w+", encoding="utf-8") as output,
        tempfile.TemporaryFile(mode="w+", encoding="utf-8") as errors,
        subprocess.Popen(arguments, stdout=output, stderr=errors, text=True) as child,
    ):
        pidfd = os.pidfd_open(child.pid)
        try:
            if not select.select([pidfd], [], [], timeout)[0]:
                child.kill()
                child.wait()
                raise subprocess.TimeoutExpired(arguments, timeout)
            status = child.wait()
        finally:
            os.close(pidfd)
        output.seek(0)
        errors.seek(0)
        return subprocess.CompletedProcess(
            arguments, status, output.read(), errors.read()
        )


def _main() -> int:
    if sys.argv[1:] == ["--workload"]:
        _workload()
        return 0
    systemd_run = shutil.which("systemd-run")
    systemctl = shutil.which("systemctl")
    if systemd_run is None or systemctl is None:
        sys.stderr.write("This test requires systemd-run and systemctl\n")
        return 1
    for prefix in ("app-org.chromium.Chromium-", "app-Hyprland-chatgpt-"):
        if _check_scope(systemd_run, systemctl, prefix) != 0:
            return 1
    return 0


def _check_scope(systemd_run: str, systemctl: str, prefix: str) -> int:
    unit = f"{prefix}oom-regression-{os.getpid()}.scope"
    # Family drop-ins override properties in a transient unit. Give only this
    # disposable scope later limits, preserving its inherited OOM policy.
    drop_in_directory = (
        Path(os.environ["XDG_RUNTIME_DIR"]) / "systemd/user" / f"{unit}.d"
    )
    drop_in_directory.mkdir(parents=True, exist_ok=False)
    limits = drop_in_directory / "99-confined-test.conf"
    try:
        limits.write_text("[Scope]\nMemoryMax=96M\nMemorySwapMax=0\n", encoding="utf-8")
        _run([systemctl, "--user", "daemon-reload"]).check_returncode()
        result = _run([
            systemd_run,
            "--user",
            "--scope",
            "--quiet",
            f"--unit={unit}",
            "--property=MemoryMax=96M",
            "--property=MemorySwapMax=0",
            sys.executable,
            str(Path(__file__).resolve()),
            "--workload",
        ])
        sys.stdout.write(result.stdout)
        if result.returncode or _SUCCESS_MESSAGE not in result.stdout:
            sys.stderr.write(
                "FAIL: confined OOM regression did not complete successfully\n"
            )
            sys.stderr.write(result.stderr)
            return 1
        return 0
    finally:
        try:
            _run([systemctl, "--user", "stop", unit])
            _run([systemctl, "--user", "reset-failed", unit])
        finally:
            limits.unlink(missing_ok=True)
            drop_in_directory.rmdir()
            _run([systemctl, "--user", "daemon-reload"]).check_returncode()


if __name__ == "__main__":
    sys.exit(_main())
