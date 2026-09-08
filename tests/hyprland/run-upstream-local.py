#!/usr/bin/env python3
"""Run local Hyprland regressions under a disposable headless Cage parent."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import shutil
import signal
import subprocess  # ruff: ignore[suspicious-subprocess-import] - This local CLI deliberately supervises test processes.
import tempfile
import time
from contextlib import suppress
from dataclasses import dataclass, field
from pathlib import Path
from typing import TypedDict, cast

# Match the other local heavy-work runners and keep Wayland socket paths short.
_TEMP_ROOT = Path("/tmp")  # ruff: ignore[hardcoded-temp-file] - Private children are created with mkdtemp.
_LOCK_PATH = _TEMP_ROOT / "nix-conf-heavy-work.lock"


class _Instance(TypedDict):
    pid: int
    instance: str
    wl_socket: str


class _Monitor(TypedDict):
    name: str


@dataclass
class _Options:
    tree: Path
    evidence: Path
    cage: str
    protocol: bool
    tests: list[str]


def _parse_options() -> _Options:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tree", type=Path)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--cage", required=True)
    parser.add_argument("--protocol", action="store_true")
    parser.add_argument("tests", nargs="*")
    args = parser.parse_args()
    return _Options(
        args.tree.resolve(),
        args.evidence.resolve(),
        args.cage,
        args.protocol,
        args.tests,
    )


def _environment(runtime: Path, evidence: Path) -> dict[str, str]:
    env = os.environ.copy()
    env.update(
        XDG_RUNTIME_DIR=str(runtime),
        WAYLAND_DISPLAY=str(runtime / "absent"),
        XDG_CACHE_HOME=str(evidence / "cache"),
        XDG_STATE_HOME=str(evidence / "state"),
        XDG_CONFIG_HOME=str(evidence / "config"),
        HYPRLAND_INSTANCE_SIGNATURE="",
        DBUS_SESSION_BUS_ADDRESS=f"unix:path={runtime}/no-bus",
        HYPRLAND_NO_SD_VARS="1",
        HYPRLAND_NO_SD_TARGET="1",
        HYPRLAND_NO_SD_NOTIFY="1",
        AQ_DRM_DEVICES="/dev/dri/renderD128",
        __EGL_VENDOR_LIBRARY_FILENAMES="/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json",
    )
    for key in ("DISPLAY", "WAYLAND_SOCKET", "SESSION_MANAGER"):
        env.pop(key, None)
    return env


def _copy_logs(directory: Path, evidence: Path) -> None:
    for path in directory.rglob("*.log"):
        shutil.copy2(path, evidence / path.name)


def _collect_protocol_logs(evidence: Path) -> None:
    test_log = evidence / "test.log"
    if not test_log.exists():
        return
    temporary_root = Path(tempfile.gettempdir()).resolve()
    for line in test_log.read_text(encoding="utf-8").splitlines():
        if line.startswith(("Test output: ", "Runtime output: ")):
            directory = Path(line.split(": ", 1)[1]).resolve()
            # Paths are emitted by the local shell runner's mktemp calls.
            if directory.parent in {_TEMP_ROOT, temporary_root} and directory.is_dir():
                _copy_logs(directory, evidence)
                shutil.rmtree(directory)


def _record_result(evidence: Path, result: int) -> int:
    crash_reports = sorted(
        str(path.relative_to(evidence))
        for path in evidence.rglob("hyprlandCrashReport*.txt")
    )
    if crash_reports:
        (evidence / "detected-crash-reports.json").write_text(
            json.dumps(crash_reports, indent=2) + "\n",
            encoding="utf-8",
        )
        if result == 0:
            result = 2
    (evidence / "exit-status.txt").write_text(str(result) + "\n", encoding="utf-8")
    print(f"Exit status: {result}; evidence: {evidence}", flush=True)  # ruff: ignore[print] - CLI progress.
    return result


@dataclass
class _Runner:
    options: _Options
    runtime: Path
    env: dict[str, str]
    processes: list[subprocess.Popen[bytes]] = field(default_factory=list)

    def _start(
        self,
        command: list[str],
        name: str,
        run_env: dict[str, str] | None = None,
    ) -> subprocess.Popen[bytes]:
        print(f"Starting {command}", flush=True)  # ruff: ignore[print] - CLI progress.
        with (self.options.evidence / name).open("w", encoding="utf-8") as output:
            proc = subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] - Explicit local executable argv, no shell.
                command,
                env=self.env if run_env is None else run_env,
                cwd=self.options.tree,
                stdout=output,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
        self.processes.append(proc)
        return proc

    def _ctl(self, *command: str) -> str:
        return subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed local hyprctl executable, no shell.
            [str(self.options.tree / "build/hyprctl/hyprctl"), *command],
            env=self.env,
            timeout=0.5,
            stderr=subprocess.DEVNULL,
            text=True,
        )

    def _start_parent(self) -> None:
        cage_env = self.env | {
            "WLR_BACKENDS": "headless",
            "WLR_RENDERER": "gles2",
            "WLR_RENDER_DRM_DEVICE": "/dev/dri/renderD128",
        }
        cage = self._start(
            [self.options.cage, "--", "sleep", "1800"], "cage.log", cage_env
        )
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            sockets = [p for p in self.runtime.glob("wayland-*") if p.is_socket()]
            if sockets:
                self.env["WAYLAND_DISPLAY"] = str(sockets[0])
                return
            if cage.poll() is not None:
                message = "Headless parent exited"
                raise RuntimeError(message)
            time.sleep(0.05)
        message = "No headless parent socket"
        raise TimeoutError(message)

    def _verify_once(self) -> bool:
        instances = cast("list[_Instance]", json.loads(self._ctl("instances", "-j")))
        if len(instances) != 1:
            time.sleep(0.05)
            return False
        instance = instances[0]
        if (
            Path(f"/proc/{instance['pid']}/exe").resolve()
            != self.options.tree / "build/Hyprland"
        ):
            message = "Unexpected compositor executable"
            raise RuntimeError(message)
        self._ctl(
            "-i", instance["instance"], "output", "create", "headless", "HEADLESS-2"
        )
        monitors = cast(
            "list[_Monitor]",
            json.loads(self._ctl("-i", instance["instance"], "monitors", "all", "-j")),
        )
        if not monitors:
            return False
        if not all(m["name"].startswith(("HEADLESS-", "WAYLAND-")) for m in monitors):
            message = "Unexpected physical output"
            raise RuntimeError(message)
        socket = self.runtime / instance["wl_socket"]
        if not socket.is_socket() or socket == Path(self.env["WAYLAND_DISPLAY"]):
            message = "Unexpected client socket"
            raise RuntimeError(message)
        report = {
            "instance": instance,
            "monitors": monitors,
            "environment": {
                k: self.env[k]
                for k in (
                    "XDG_RUNTIME_DIR",
                    "WAYLAND_DISPLAY",
                    "AQ_DRM_DEVICES",
                    "DBUS_SESSION_BUS_ADDRESS",
                    "XDG_CACHE_HOME",
                    "XDG_STATE_HOME",
                )
            },
        }
        (self.options.evidence / "isolation.json").write_text(
            json.dumps(report, indent=2),
            encoding="utf-8",
        )
        return True

    def _try_verify(self) -> bool:
        try:
            return self._verify_once()
        except (subprocess.SubprocessError, json.JSONDecodeError, FileNotFoundError):
            time.sleep(0.05)
            return False

    def _verify(self) -> None:
        # hyprtester waits ten seconds before loading its plugin or running tests.
        # Verify its sole private instance and outputs within eight seconds.
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            if self._try_verify():
                print(  # ruff: ignore[print] - CLI progress.
                    "Verified private instance, client socket, and headless/nested outputs",
                    flush=True,
                )
                return
        message = "Could not verify isolation before test startup"
        raise TimeoutError(message)

    def _run_tests(self) -> int:
        if self.options.protocol:
            self.env.update(KEEP_TEST_OUTPUT="1", HYPRLAND_TEST_HEADLESS="1")
            script = Path(__file__).with_name("check-subsurface-teardown.sh")
            proc = self._start(
                ["bash", str(script), str(self.options.tree / "build/Hyprland")],
                "test.log",
            )
            return proc.wait(timeout=240)
        config = self.options.evidence / "test.lua"
        shutil.copytree(
            self.options.tree / "hyprtester/lua-require",
            self.options.evidence / "lua-require",
        )
        shutil.copy2(self.options.tree / "hyprtester/test.lua", config)
        command = [
            str(self.options.tree / "build/hyprtester/hyprtester"),
            "-c",
            str(config),
            "-b",
            str(self.options.tree / "build/Hyprland"),
            "-p",
            str(self.options.tree / "hyprtester/plugin/hyprtestplugin.so"),
            *self.options.tests,
        ]
        (self.options.evidence / "command.json").write_text(
            json.dumps(command, indent=2) + "\n",
            encoding="utf-8",
        )
        proc = self._start(command, "test.log")
        self._verify()
        return proc.wait(timeout=1500 if not self.options.tests else 180)

    def _stop(self) -> None:
        test_log = self.options.evidence / "test.log"
        if test_log.exists() and "Hyprland has crashed" in test_log.read_text(
            encoding="utf-8", errors="replace"
        ):
            # hyprtester requests compositor exit and immediately sends SIGKILL.
            # Give its crash reporter time to finish before terminating the group.
            time.sleep(3)
        for proc in reversed(self.processes):
            with suppress(ProcessLookupError):
                os.killpg(proc.pid, signal.SIGTERM)
        time.sleep(0.3)
        for proc in reversed(self.processes):
            with suppress(ProcessLookupError):
                os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=5)

    def run(self) -> int:
        """Run the isolated tests and retain logs after stopping the children.

        Returns:
            The test exit status, or 2 when a successful test left a crash report.

        """
        result = 1
        try:
            self._start_parent()
            result = self._run_tests()
        finally:
            self._stop()
            _copy_logs(self.runtime, self.options.evidence)
            if self.options.protocol:
                _collect_protocol_logs(self.options.evidence)
            result = _record_result(self.options.evidence, result)
        return result


def main() -> int:
    """Serialize local heavy work and create a disposable runtime directory.

    Returns:
        The test exit status, or 2 when a successful test left a crash report.

    """
    options = _parse_options()
    options.evidence.mkdir(parents=True, exist_ok=False)
    with _LOCK_PATH.open("a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with tempfile.TemporaryDirectory(prefix="hu.", dir=_TEMP_ROOT) as runtime:
            runner = _Runner(
                options, Path(runtime), _environment(Path(runtime), options.evidence)
            )
            return runner.run()


if __name__ == "__main__":
    raise SystemExit(main())
