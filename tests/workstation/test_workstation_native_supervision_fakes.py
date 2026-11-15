"""Bounded source-function tests without runtime import, host effects or children."""

import ast
import asyncio
import contextlib
import os
import re
import signal
import subprocess  # ruff: ignore[suspicious-subprocess-import] - only exception class used; never execute subprocesses
from dataclasses import dataclass, field
from pathlib import Path
from types import SimpleNamespace
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from collections.abc import Iterable, Iterator

SOURCE = Path(
    os.environ.get(
        "SUPERVISOR_SOURCE",
        Path(__file__).parents[2]
        / "modules/home/services/workstation-jobs-assets/workstation_job.py",
    )
)
MIB = 1024**2
GIB = 1024**3
PAYLOAD_PID = 4402
SAMPLER_PID = 5501
MAX_WAITS = 20


def functions() -> dict:
    """Compile only the agreed functions with explicit effectful globals.

    Returns:
        The captured functions and their isolated global namespace.

    """
    tree = ast.parse(SOURCE.read_text(encoding="utf-8"))
    names = {"_supervise", "_darwin_available", "_memory_sample", "_vm_available"}
    selected = [
        node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name in names
    ]
    assert len(selected) == len(names)
    module = ast.Module(
        body=[
            ast.ImportFrom(
                module="__future__", names=[ast.alias(name="annotations")], level=0
            ),
            *selected,
        ],
        type_ignores=[],
    )
    scope = {
        "contextlib": contextlib,
        "signal": signal,
        "re": re,
        "subprocess": SimpleNamespace(SubprocessError=subprocess.SubprocessError),
        "MIB": MIB,
    }
    # Only pinned AST-selected functions execute, with fake effectful globals.
    exec(compile(ast.fix_missing_locations(module), str(SOURCE), "exec"), scope)  # ruff: ignore[exec-builtin]
    return scope


class FakePath:
    """Represent an absent cancellation marker without filesystem access."""

    def __truediv__(self, _name: str) -> FakePath:
        """Keep marker paths within this fake.

        Returns:
            This same absent path.

        """
        return self

    @staticmethod
    def exists() -> bool:
        """Report the marker absent.

        Returns:
            False for every marker lookup.

        """
        return False


@dataclass
class Scenario:
    """Supply explicit process, clock, sampler and signal boundary fakes."""

    samples: Iterable[str] = ("timeout", "ok")
    rss: Iterable[int | str] = (8, 8, 0)
    cancel: bool = False
    timeout: float = 20
    deny: int | None = None
    low: bool = False
    invalid: bool = False
    backend: str = "darwin"
    sampler_denial: bool = False
    scope: dict = field(default_factory=functions, init=False)
    now: float = field(default=0, init=False)
    calls: list[tuple[str, float]] = field(default_factory=list, init=False)
    signals: list[tuple[int, int]] = field(default_factory=list, init=False)
    saved: list[dict] = field(default_factory=list, init=False)
    waits: int = field(default=0, init=False)
    event: asyncio.Event = field(init=False)
    sample_values: Iterator[str] = field(init=False)
    rss_values: Iterator[int | str] = field(init=False)

    async def _spawn(self, *args: str, **kwargs: object) -> SimpleNamespace:
        assert args == (
            ("fake-payload",)
            if self.backend == "darwin"
            else ("fake-runner", "--feedback", "fake-payload")
        )
        assert kwargs["start_new_session"] is True
        return SimpleNamespace(pid=PAYLOAD_PID, wait=self._process_wait)

    @staticmethod
    async def _process_wait() -> int:
        return 0

    @staticmethod
    async def _connect(*_args: object) -> tuple[SimpleNamespace, None]:
        return SimpleNamespace(close=lambda: None), None

    def _event(self) -> asyncio.Event:
        self.event = asyncio.Event()
        return self.event

    async def _wait(
        self,
        tasks: set[asyncio.Task],
        *,
        timeout: float,  # ruff: ignore[async-function-with-timeout] - asyncio.wait protocol
        return_when: str,  # ruff: ignore[unused-method-argument] - asyncio.wait protocol
    ) -> tuple[set[asyncio.Task], set[asyncio.Task]]:
        self.waits += 1
        assert self.waits <= MAX_WAITS, "unbounded fake supervision"
        await asyncio.sleep(0)
        self.now += timeout
        return {task for task in tasks if task.done()}, set()

    @staticmethod
    async def _output(*_args: object) -> bool:
        return False

    async def _usage(self, *_args: object, **_kwargs: object) -> int:
        sample = next(self.rss_values, 0)
        if sample == "timeout":
            if self.cancel:
                self.event.set()
            self.now += 1
            raise TimeoutError
        assert isinstance(sample, int)
        return sample * MIB

    async def _sample(
        self,
        command: list[str],
        cancelled: asyncio.Event,
        seconds: float,
        **_kwargs: object,
    ) -> str:
        if self.sampler_denial:
            error = PermissionError(1, "fake sampler cleanup denied")
            error.native_cleanup_observation = {
                "operation": "sampler-group-signal",
                "errorType": "PermissionError",
                "pid": SAMPLER_PID,
                "processGroup": SAMPLER_PID,
                "signal": 15,
            }
            raise error
        self.calls.append((command[0], seconds))
        assert 0 < seconds <= 1
        if command[0] == "/usr/sbin/sysctl":
            value = next(self.sample_values, "ok")
            if value == "timeout":
                if self.cancel:
                    cancelled.set()
                self.now += seconds
                raise TimeoutError
            if self.invalid:
                message = "fake malformed observation"
                raise ValueError(message)
            return "2" if self.low else "1"
        assert command == ["/usr/bin/vm_stat"]
        return "Mach Virtual Memory Statistics: (page size of 4096 bytes)\nPages free: 262144.\n"

    def _killpg(self, pid: int, sig: int) -> None:
        assert pid == PAYLOAD_PID
        self.signals.append((pid, sig))
        if self.deny == sig:
            raise PermissionError(1, "fake denied")
        if sig == 0:
            raise ProcessLookupError

    @staticmethod
    async def _grow(
        _recipe: dict,
        _directory: FakePath,
        memory: int,
        _usage: int,
        healthy: float | None,
        _cancelled: asyncio.Event,
        _seconds: float,
    ) -> tuple[int, float | None]:
        return memory, healthy

    async def run(self) -> dict:
        """Run the captured supervisor against only these boundary fakes.

        Returns:
            Its terminal receipt after bounded in-memory supervision.

        """
        self.sample_values = iter(self.samples)
        self.rss_values = iter(self.rss)
        loop = SimpleNamespace(
            add_signal_handler=lambda *_args: None, connect_read_pipe=self._connect
        )
        self.scope.update(
            asyncio=SimpleNamespace(
                Event=self._event,
                get_running_loop=lambda: loop,
                StreamReader=lambda: None,
                StreamReaderProtocol=lambda _: None,
                create_subprocess_exec=self._spawn,
                create_task=asyncio.create_task,
                wait=self._wait,
                wait_for=asyncio.wait_for,
                shield=asyncio.shield,
                FIRST_COMPLETED=asyncio.FIRST_COMPLETED,
                CancelledError=asyncio.CancelledError,
                subprocess=asyncio.subprocess,
            ),
            os=SimpleNamespace(
                getpid=lambda: 4401,
                pipe=lambda: (11, 12),
                fdopen=lambda *_args, **_kwargs: None,
                close=lambda _: None,
                killpg=self._killpg,
            ),
            time=SimpleNamespace(monotonic=lambda: self.now, time=lambda: self.now),
            platform=SimpleNamespace(node=lambda: "fake-host"),
            LIFECYCLE_VERSION=2,
            _save=lambda _path, receipt: self.saved.append(dict(receipt)),
            _read=lambda _: {},
            _execution_environment=lambda *_args: {},
            _process_identity=lambda *_args: "fake-birth",
            _available=lambda: 1024**4,
            _host_memory_pressure=lambda: "normal",
            _group_usage=self._usage,
            _memory_sample=self._sample,
            _output=self._output,
            _grow_darwin=self._grow,
            _allows_daemon=lambda *_args: False,
            _mode=lambda *_args: "feedback",
            _owner_unit=lambda *_args: "fake-owner",
        )
        recipe = {
            "id": "fixture",
            "profile": "bounded",
            "memoryMiB": 256,
            "timeout": self.timeout,
            "sourceReference": "frozen-fake",
            "command": ["fake-payload"],
            "cwd": "fake-directory",
            "config": {
                "profiles": {"bounded": {"backend": self.backend}},
                "reserveMiB": 1,
                "ps": "fake-ps",
                "workstationTask": "fake-runner",
            },
        }
        code = await self.scope["_supervise"](recipe, FakePath())
        receipt = self.saved[-1]
        assert receipt["exitCode"] == code
        return receipt


def test_single_capacity_timeout_recovers_with_unknown_observation_counted() -> None:
    """Single capacity timeout recovers with unknown observation counted."""
    scenario = Scenario()
    receipt = asyncio.run(scenario.run())
    assert receipt["phase"] == "succeeded"
    assert receipt["hostMemorySamplingTimeouts"] == 1
    assert receipt["hostMemorySamplingConsecutiveTimeouts"] == 0


def test_repeated_capacity_timeout_fails_closed_even_after_zero_rss() -> None:
    """Repeated capacity timeout fails closed even after zero rss."""
    expected_misses = 2
    receipt = asyncio.run(Scenario(samples=("timeout", "timeout"), rss=(8, 0)).run())
    assert receipt["phase"] == "supervision-error"
    assert receipt["hostMemorySamplingTimeouts"] == expected_misses
    assert receipt["hostMemorySamplingConsecutiveTimeouts"] == expected_misses
    assert receipt["hostMemoryObservation"]["availableBytes"] is None
    assert receipt["supervisionErrorOperation"] == "host-capacity"
    assert receipt["memorySamplingTimeouts"] == 0


@pytest.mark.parametrize("cancel", [False, True])
def test_capacity_retry_keeps_cancellation_and_absolute_deadline(cancel: bool) -> None:
    """Capacity retry keeps cancellation and absolute deadline."""
    scenario = Scenario(cancel=cancel, timeout=1)
    receipt = asyncio.run(scenario.run())
    assert receipt["phase"] == ("cancelled" if cancel else "timeout")
    assert receipt["hostMemorySamplingTimeouts"] == 1
    assert scenario.now <= 1 + 0.01


@pytest.mark.parametrize(
    ("rss", "phase", "count"),
    [
        ((8, "timeout", 0), "succeeded", 1),
        ((8, "timeout", "timeout"), "supervision-error", 2),
    ],
)
def test_rss_sampling_policy_is_preserved(
    rss: tuple[int | str, ...], phase: str, count: int
) -> None:
    """Rss sampling policy is preserved."""
    receipt = asyncio.run(Scenario(samples=("ok",), rss=rss).run())
    assert receipt["phase"] == phase
    assert receipt["memorySamplingTimeouts"] == count
    assert receipt["hostMemorySamplingTimeouts"] == 0


@pytest.mark.parametrize("cancel", [False, True])
def test_rss_timeout_keeps_cancellation_and_deadline(cancel: bool) -> None:
    """Rss timeout keeps cancellation and deadline."""
    receipt = asyncio.run(Scenario(rss=("timeout",), cancel=cancel, timeout=1).run())
    assert receipt["phase"] == ("cancelled" if cancel else "timeout")
    assert receipt["memorySamplingTimeouts"] == 1


def test_recovered_capacity_still_enforces_pressure_and_reserve() -> None:
    """Recovered capacity still enforces pressure and reserve."""
    receipt = asyncio.run(Scenario(low=True).run())
    assert receipt["phase"] == "host-memory-headroom-lost"
    assert receipt["hostMemoryObservation"]["availableBytes"] == 0


def test_non_timeout_capacity_error_is_not_retried() -> None:
    """Non timeout capacity error is not retried."""
    receipt = asyncio.run(Scenario(samples=("ok",), invalid=True).run())
    assert receipt["phase"] == "supervision-error"
    assert receipt["supervisionErrorType"] == "ValueError"
    assert receipt["hostMemorySamplingTimeouts"] == 0


def test_rss_memory_limit_still_enforced() -> None:
    """Rss memory limit still enforced."""
    receipt = asyncio.run(Scenario(rss=(257,)).run())
    assert receipt["phase"] == "memory-limit-observed"


def test_signal_denial_preserved_despite_final_absence() -> None:
    """Signal denial preserved despite final absence."""
    receipt = asyncio.run(
        Scenario(low=True, samples=("ok",), deny=signal.SIGTERM).run()
    )
    assert receipt["nativeCleanupErrorTypes"] == ["PermissionError"]
    assert not receipt["drained"]
    assert receipt["nativeGroupAbsent"]
    assert {
        "operation": "payload-group-signal",
        "errorType": "PermissionError",
        "pid": 4402,
        "processGroup": 4402,
        "signal": int(signal.SIGTERM),
    } in receipt["nativeCleanupErrors"]


def test_final_absence_denial_remains_unknown_and_undrained() -> None:
    """Final absence denial remains unknown and undrained."""
    receipt = asyncio.run(Scenario(samples=("ok",), deny=0).run())
    assert not receipt["drained"]
    assert not receipt["nativeGroupAbsent"]
    assert {
        "operation": "payload-group-absence",
        "errorType": "PermissionError",
        "pid": 4402,
        "processGroup": 4402,
        "signal": 0,
    } in receipt["nativeCleanupErrors"]


def test_sampler_cleanup_denial_is_carried_into_terminal_receipt() -> None:
    """Sampler cleanup denial is carried into terminal receipt."""
    receipt = asyncio.run(Scenario(sampler_denial=True).run())
    assert receipt["phase"] == "supervision-error"
    assert receipt["supervisionErrorOperation"] == "host-capacity"
    assert receipt["nativeCleanupErrorTypes"] == ["PermissionError"]
    assert not receipt["drained"]
    assert receipt["nativeGroupAbsent"]
    assert receipt["nativeCleanupErrors"][0]["processGroup"] == SAMPLER_PID


def test_linux_desktop_backend_never_uses_native_sampling() -> None:
    """Linux desktop backend never uses native sampling."""
    scenario = Scenario(backend="desktop")
    receipt = asyncio.run(scenario.run())
    assert receipt["phase"] == "succeeded"
    assert scenario.calls == []
    assert "hostMemorySamplingTimeouts" not in receipt
    assert "nativeCleanupErrors" not in receipt


def test_separated_capacity_misses_reset_only_after_measured_recovery() -> None:
    """Separated capacity misses reset only after measured recovery."""
    expected_misses = 2
    scenario = Scenario(samples=("timeout", "ok", "timeout", "ok"), rss=(8, 8, 8, 8, 0))
    receipt = asyncio.run(scenario.run())
    assert receipt["phase"] == "succeeded"
    assert receipt["hostMemorySamplingTimeouts"] == expected_misses
    assert receipt["hostMemorySamplingConsecutiveTimeouts"] == 0
    assert receipt["hostMemoryObservation"]["availableBytes"] == GIB


def test_pressure_and_vm_stat_share_one_sampling_deadline() -> None:
    """Pressure and vm stat share one sampling deadline."""

    async def run() -> None:
        scope = functions()
        clock = [0.0]
        calls = []

        async def sample(  # ruff: ignore[unused-async] - async boundary protocol fake
            command: list[str], _cancelled: asyncio.Event, seconds: float
        ) -> str:
            calls.append((command[0], seconds))
            if command[0] == "/usr/sbin/sysctl":
                clock[0] += 0.4
                return "1"
            raise TimeoutError

        scope.update(
            time=SimpleNamespace(monotonic=lambda: clock[0]), _memory_sample=sample
        )
        with pytest.raises(TimeoutError):
            await scope["_darwin_available"](asyncio.Event(), 1)
        assert calls[0] == ("/usr/sbin/sysctl", 1)
        assert calls[1] == ("/usr/bin/vm_stat", 0.6)

    asyncio.run(run())


def test_unknown_pressure_never_reads_as_healthy_capacity() -> None:
    """Unknown pressure never reads as healthy capacity."""

    async def run() -> None:
        scope = functions()
        calls = []

        async def sample(  # ruff: ignore[unused-async] - async boundary protocol fake
            command: list[str], _cancelled: asyncio.Event, _seconds: float
        ) -> str:
            calls.append(command[0])
            return "unknown"

        scope.update(time=SimpleNamespace(monotonic=lambda: 0), _memory_sample=sample)
        assert await scope["_darwin_available"](asyncio.Event(), 1) == 0
        assert calls == ["/usr/sbin/sysctl"]

    asyncio.run(run())


@pytest.mark.parametrize("sig", [signal.SIGTERM, signal.SIGKILL])
def test_sampler_denied_cleanup_reports_owned_sampler_not_payload(sig: int) -> None:
    """Sampler denied cleanup reports owned sampler not payload."""

    async def run() -> None:
        scope = functions()
        pending = asyncio.Event()

        async def communicate() -> tuple[bytes, bytes]:
            await pending.wait()
            return (b"", b"")

        async def spawn(*_args: object, **_kwargs: object) -> SimpleNamespace:  # ruff: ignore[unused-async] - async boundary protocol fake
            return SimpleNamespace(pid=5501, communicate=communicate)

        async def wait(*_args: object, **_kwargs: object) -> tuple[set, set]:  # ruff: ignore[unused-async] - async boundary protocol fake
            return (set(), set())

        async def wait_for(_task: asyncio.Task, timeout: float) -> None:  # ruff: ignore[async-function-with-timeout, unused-function-argument, unused-async] - async boundary protocol fake
            raise TimeoutError

        def killpg(pid: int, selected: int) -> None:
            assert pid == SAMPLER_PID
            if selected == sig:
                raise PermissionError(1, "fake denial")

        scope.update(
            asyncio=SimpleNamespace(
                create_subprocess_exec=spawn,
                create_task=asyncio.create_task,
                wait=wait,
                wait_for=wait_for,
                shield=asyncio.shield,
                subprocess=asyncio.subprocess,
                FIRST_COMPLETED=asyncio.FIRST_COMPLETED,
                CancelledError=asyncio.CancelledError,
            ),
            os=SimpleNamespace(killpg=killpg),
        )
        before = asyncio.all_tasks()
        try:
            with pytest.raises(PermissionError) as caught:
                await scope["_memory_sample"](["/usr/bin/vm_stat"], asyncio.Event(), 1)
            assert caught.value.native_cleanup_observation == {
                "operation": "sampler-group-signal",
                "errorType": "PermissionError",
                "pid": 5501,
                "processGroup": 5501,
                "signal": int(sig),
            }
        finally:
            for task in asyncio.all_tasks() - before:
                task.cancel()
            await asyncio.gather(*asyncio.all_tasks() - before, return_exceptions=True)

    asyncio.run(run())
