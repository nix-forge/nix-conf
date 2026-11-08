"""Real lock contention with private queues and simulated executor drain.

These tests establish serialization of cooperating runner and backup callers.
They do not establish host-wide memory reservations for direct Nix clients.
"""
# Disposable executables retain real flock while replacing host manager access.

import asyncio
import contextlib
import shlex
import shutil
import sys
from dataclasses import dataclass, field
from pathlib import Path

import pytest
from systemd.test_workstation_backup_lock import executable, fixtures

pytestmark = pytest.mark.skipif(
    not sys.platform.startswith("linux") or not shutil.which("flock"),
    reason="Linux real flock required",
)


@dataclass
class AdmissionFixture:
    """Own every disposable process and drain notification in one scenario."""

    work: Path
    runner: str
    backup: str
    worker: str
    environment: dict[str, str]
    jobs: list[asyncio.subprocess.Process] = field(default_factory=list)

    async def start(
        self, kind: str, *, runner: str | None = None
    ) -> asyncio.subprocess.Process:
        """Start a private managed lane or root-backup-equivalent command.

        Returns:
            The owned asynchronous subprocess.

        """
        options = {
            "bulk": [],
            "feedback": ["--feedback"],
            "bounded": ["--bounded-memory", "1"],
        }
        command = (
            [self.backup]
            if kind == "backup"
            else [runner or self.runner, *options[kind], self.worker]
        )
        job = await asyncio.create_subprocess_exec(
            *command,
            env=self.environment,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        self.jobs.append(job)
        return job

    @staticmethod
    async def ready(job: asyncio.subprocess.Process) -> None:
        """Wait for the marker payload, rather than assuming it has launched."""
        assert job.stdout is not None
        assert await asyncio.wait_for(job.stdout.readline(), 5) == b"ready\n"

    @staticmethod
    async def attempting(job: asyncio.subprocess.Process, lock: str) -> None:
        """Observe a real flock attempt before asserting the payload is blocked."""
        assert job.stderr is not None
        async with asyncio.timeout(5):
            while line := await job.stderr.readline():
                if line == f"lock-attempt:{lock}\n".encode():
                    return
        pytest.fail("Process exited before attempting its private admission lock")

    @staticmethod
    async def finish_payload(job: asyncio.subprocess.Process) -> None:
        """Let the foreground exit without declaring its execution scope drained."""
        assert job.stdin is not None
        job.stdin.write(b"done\n")
        await job.stdin.drain()

    async def drain(self, job: asyncio.subprocess.Process) -> None:
        """Release one fake cgroup-empty notification after foreground exit."""
        assert job.stdout is not None
        line = await asyncio.wait_for(job.stdout.readline(), 5)
        assert line.startswith(b"draining:")
        unit = line.decode().strip().removeprefix("draining:")
        fifo = self.work / "sysfs" / "fixture" / unit / "drain"

        def notify() -> None:
            with fifo.open("w", encoding="utf-8") as stream:
                stream.write("empty\n")

        await asyncio.wait_for(asyncio.to_thread(notify), 5)

    @staticmethod
    async def completed(job: asyncio.subprocess.Process, code: int = 0) -> None:
        """Require terminal completion, including the runner's cleanup path."""
        assert await asyncio.wait_for(job.wait(), 5) == code

    async def close(self) -> None:
        """Terminate only fixture-owned commands, including canceled waiters."""
        for job in reversed(self.jobs):
            if job.returncode is None:
                with contextlib.suppress(ProcessLookupError):
                    job.terminate()
                try:
                    await asyncio.wait_for(job.wait(), 5)
                except TimeoutError:
                    job.kill()
                    await job.wait()


@pytest.fixture
def admission(tmp_path: Path) -> AdmissionFixture:
    """Render the production runner with no access to host locks or managers.

    Returns:
        A private process owner with real flock and controlled memory snapshots.

    """
    runner, backup, worker, environment = fixtures(tmp_path)
    real_flock = shutil.which("flock")
    assert real_flock is not None
    executable(
        tmp_path / "flock",
        "#!/usr/bin/env bash\n"
        "if [[ $* == *shared.lock* ]]; then\n"
        " printf 'lock-attempt:8\\n' >&2\n"
        "else\n printf 'lock-attempt:%s\\n' \"${@: -1}\" >&2\nfi\n"
        f'exec {shlex.quote(real_flock)} "$@"\n',
    )
    backup_path = Path(backup)
    backup_path.write_text(
        backup_path.read_text(encoding="utf-8").replace(
            shlex.quote(real_flock), shlex.quote(str(tmp_path / "flock"))
        ),
        encoding="utf-8",
    )
    fake_group = tmp_path / "sysfs" / "fixture"
    fake_group.mkdir(parents=True)
    (fake_group / "memory.current").write_text("0\n", encoding="utf-8")
    (fake_group / "memory.max").write_text("10737418240\n", encoding="utf-8")
    meminfo = tmp_path / "meminfo"
    # Exactly one 1 GiB bounded budget plus its 2 GiB reserve; neither agent
    # observes payload allocations, so only correct lifetime locking serializes.
    meminfo.write_text("MemAvailable: 3145728 kB\n", encoding="utf-8")
    manager = executable(
        tmp_path / "systemctl",
        f"#!{sys.executable}\n"
        "import os,sys\nfrom pathlib import Path\n"
        f"root=Path({str(fake_group)!r})\n"
        "args=sys.argv[1:]\n"
        "if 'ControlGroup' in args:\n"
        " unit=args[args.index('show')+1]\n"
        " if unit=='background-workload.slice': print('/fixture')\n"
        " else:\n"
        "  group=root/unit\n  group.mkdir(exist_ok=True)\n"
        "  fifo=group/'drain'\n"
        "  if not fifo.exists(): os.mkfifo(fifo)\n"
        "  print('/fixture/'+unit)\n"
        "elif 'Result' in args: print('success')\n"
        "elif 'background-workload.slice' in args:\n"
        " print('MemoryHigh=8589934592\\nMemoryMax=10737418240\\nMemorySwapMax=2147483648\\nManagedOOMMemoryPressure=kill')\n",
    )
    assert manager == str(tmp_path / "systemctl")
    drain = executable(
        tmp_path / "wait-for-empty",
        f"#!{sys.executable}\n"
        "import sys\nfrom pathlib import Path\n"
        "group=Path(sys.argv[1]).parent\n"
        "print('draining:'+group.name,flush=True)\n"
        "with (group/'drain').open() as stream: stream.readline()\n",
    )
    bubblewrap = executable(
        tmp_path / "bwrap",
        '#!/usr/bin/env bash\nwhile [[ ${1:-} != -- ]]; do shift; done\nshift\nexec "$@"\n',
    )
    path = Path(runner)
    source = path.read_text(encoding="utf-8")
    for old, new in {
        "@boundedReserve@": "2147483648",
        "@bubblewrap@": shlex.quote(bubblewrap),
        "/proc/meminfo": str(meminfo),
        "/sys/fs/cgroup": str(tmp_path / "sysfs"),
        'true "/': shlex.quote(drain) + ' "/',
    }.items():
        source = source.replace(old, new)
    path.write_text(source, encoding="utf-8")
    return AdmissionFixture(tmp_path, runner, backup, worker, environment)


async def assert_blocked(pending: asyncio.Task[bytes]) -> None:
    """Require a lock contender to stay outside its payload until scope drain."""
    with pytest.raises(TimeoutError):
        await asyncio.wait_for(asyncio.shield(pending), 0.15)


async def serialize(admission: AdmissionFixture, first: str, second: str) -> None:
    """Exercise actual lock ownership across payload exit and scope drain."""
    pending = None
    try:
        owner = await admission.start(first)
        await admission.ready(owner)
        waiter = await admission.start(second)
        await admission.attempting(waiter, "9" if second == "bounded" else "8")
        assert waiter.stdout is not None
        pending = asyncio.create_task(waiter.stdout.readline())
        await assert_blocked(pending)
        await admission.finish_payload(owner)
        if first != "backup":
            # Foreground exit must not release either admission lock while the
            # executor still reports an occupied scope.
            assert owner.stdout is not None
            draining = asyncio.create_task(owner.stdout.readline())
            line = await asyncio.wait_for(draining, 5)
            assert line.startswith(b"draining:")
            await assert_blocked(pending)
            unit = line.decode().strip().removeprefix("draining:")
            fifo = admission.work / "sysfs" / "fixture" / unit / "drain"
            await asyncio.to_thread(fifo.write_text, "empty\n", encoding="utf-8")
        await admission.completed(owner)
        assert await asyncio.wait_for(pending, 5) == b"ready\n"
        await admission.finish_payload(waiter)
        if second != "backup":
            await admission.drain(waiter)
        await admission.completed(waiter)
    finally:
        if pending is not None and not pending.done():
            pending.cancel()
        await admission.close()


@pytest.mark.parametrize("first", ["bulk", "feedback"])
def test_bulk_and_feedback_share_admission(
    admission: AdmissionFixture, first: str
) -> None:
    """The ordinary bulk and feedback lanes cannot launch payloads together."""
    second = "feedback" if first == "bulk" else "bulk"
    asyncio.run(serialize(admission, first, second))


@pytest.mark.parametrize("first", ["backup", "feedback"])
def test_root_backup_and_feedback_share_admission(
    admission: AdmissionFixture, first: str
) -> None:
    """The production backup lock excludes feedback in both acquisition orders."""
    second = "feedback" if first == "backup" else "backup"
    asyncio.run(serialize(admission, first, second))


def test_two_agents_cannot_spend_the_same_available_budget(
    admission: AdmissionFixture,
) -> None:
    """Competing bounded agents share one slot despite identical free-RAM reads."""
    asyncio.run(serialize(admission, "bounded", "bounded"))


def test_cancelled_feedback_waiter_releases_its_lane(
    admission: AdmissionFixture,
) -> None:
    """Canceling a real shared-lock wait cannot strand its feedback successor."""

    async def exercise() -> None:
        try:
            owner = await admission.start("backup")
            await admission.ready(owner)
            waiter = await admission.start("feedback")
            await admission.attempting(waiter, "8")
            waiter.terminate()
            await admission.completed(waiter, 143)
            successor = await admission.start("feedback")
            await admission.attempting(successor, "8")
            assert successor.stdout is not None
            pending = asyncio.create_task(successor.stdout.readline())
            try:
                await assert_blocked(pending)
                await admission.finish_payload(owner)
                await admission.completed(owner)
                assert await asyncio.wait_for(pending, 5) == b"ready\n"
            finally:
                if not pending.done():
                    pending.cancel()
            await admission.finish_payload(successor)
            await admission.drain(successor)
            await admission.completed(successor)
        finally:
            await admission.close()

    asyncio.run(exercise())


def test_feedback_order_preserves_legacy_bounded_progress(
    admission: AdmissionFixture,
) -> None:
    """Keep shared-before-feedback ordering during a mixed-version rollout."""
    source = Path(admission.runner).read_text(encoding="utf-8")
    feedback_acquisition = '  exec 7>"$XDG_RUNTIME_DIR/workstation-feedback.lock"'
    assert source.count(feedback_acquisition) == 1
    # The bounded branch retains the legacy background -> shared -> feedback
    # order. Stop it after shared ownership, before attempting feedback. With
    # a feedback-first successor, each process would then hold the other's lock.
    legacy = executable(
        admission.work / "legacy-bounded",
        source.replace(
            feedback_acquisition,
            "  printf 'legacy-shared-held\\n'\n"
            "  IFS= read -r legacy_release\n" + feedback_acquisition,
        ),
    )

    async def exercise() -> None:
        pending = None
        try:
            owner = await admission.start("bounded", runner=legacy)
            assert owner.stdout is not None
            assert (
                await asyncio.wait_for(owner.stdout.readline(), 5)
                == b"legacy-shared-held\n"
            )
            successor = await admission.start("feedback")
            await admission.attempting(successor, "8")
            assert successor.stdout is not None
            pending = asyncio.create_task(successor.stdout.readline())
            await assert_blocked(pending)
            # Release the legacy barrier. Its payload must launch while the
            # successor waits on shared, proving feedback is still available.
            await admission.finish_payload(owner)
            await admission.ready(owner)
            await assert_blocked(pending)
            await admission.finish_payload(owner)
            await admission.drain(owner)
            await admission.completed(owner)
            assert await asyncio.wait_for(pending, 5) == b"ready\n"
            await admission.finish_payload(successor)
            await admission.drain(successor)
            await admission.completed(successor)
        finally:
            if pending is not None and not pending.done():
                pending.cancel()
            await admission.close()

    asyncio.run(exercise())
