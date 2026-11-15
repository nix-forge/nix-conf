"""Native bounded-lane integration; each child belongs to this probe's own scope."""

import asyncio
import json
import os
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Launch only this probe's fixed child program.
import sys
from pathlib import Path


class Probe:
    """Own and clean up the small set of native fixture processes."""

    def __init__(self, runner: str) -> None:
        """Keep the fixed runner and owned subprocess handles."""
        self.runner = runner
        self.jobs: list[asyncio.subprocess.Process] = []

    async def start(
        self, mode: str = "hold", runner: str | None = None
    ) -> asyncio.subprocess.Process:
        """Start one bounded native fixture through the candidate runner.

        Returns:
            The owned subprocess with readiness and release pipes.

        """
        job = await asyncio.create_subprocess_exec(
            runner or self.runner,
            "--feedback",
            sys.executable,
            __file__,
            "--child",
            mode,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        self.jobs.append(job)
        return job

    async def clean(self) -> None:
        """Cancel only fixtures created by this probe."""
        for job in self.jobs:
            if job.returncode is None:
                job.terminate()
                await asyncio.wait_for(job.wait(), 10)


async def ready(job: asyncio.subprocess.Process) -> dict[str, str]:
    """Wait on the child's readiness pipe rather than polling its process.

    Returns:
        The child-reported scope identity.

    Raises:
        AssertionError: The launcher exited before readiness.

    """
    assert job.stdout is not None
    assert job.stderr is not None
    line = await asyncio.wait_for(job.stdout.readline(), 10)
    if not line:
        raise AssertionError((await job.stderr.read()).decode())
    return json.loads(line)


async def release(job: asyncio.subprocess.Process) -> None:
    """Release the fixture's stdin gate and require successful completion."""
    assert job.stdin is not None
    job.stdin.write(b"release\n")
    await job.stdin.drain()
    assert await asyncio.wait_for(job.wait(), 10) == 0


async def remains_queued(job: asyncio.subprocess.Process) -> asyncio.Task[bytes]:
    """Prove the successor has not started while its lane is occupied.

    Returns:
        The pending readiness notification for later completion.

    Raises:
        AssertionError: The successor started before the owner released its lane.

    """
    assert job.stdout is not None
    pending = asyncio.create_task(job.stdout.readline())
    try:
        await asyncio.wait_for(asyncio.shield(pending), 0.15)
    except TimeoutError:
        return pending
    message = "Concurrent feedback checks overlapped"
    raise AssertionError(message)


async def resource_and_serialization(probe: Probe) -> None:
    """Check actual caps, same-lane order and private queue timing."""
    first = await probe.start()
    info = await ready(first)
    unit = info["scope"].split("/")[-1]
    query = await asyncio.create_subprocess_exec(
        "systemctl",
        "--user",
        "show",
        unit,
        "-p",
        "MemoryMax",
        "-p",
        "MemoryHigh",
        "-p",
        "MemorySwapMax",
        "-p",
        "RuntimeMaxUSec",
        "-p",
        "CPUQuotaPerSecUSec",
        stdout=asyncio.subprocess.PIPE,
    )
    props = dict(
        line.split("=", 1)
        for line in (await query.communicate())[0].decode().splitlines()
    )
    assert props == {
        "MemoryMax": "2147483648",
        "MemoryHigh": "1879048192",
        "MemorySwapMax": "268435456",
        "RuntimeMaxUSec": "2min",
        "CPUQuotaPerSecUSec": "1s",
    }, props
    second = await probe.start()
    pending = await remains_queued(second)
    await release(first)
    assert json.loads(await asyncio.wait_for(pending, 10))["scope"] != info["scope"]
    await release(second)
    event = (
        Path(os.environ["XDG_RUNTIME_DIR"])
        / "workstation-task-events"
        / (unit + ".json")
    )
    record = json.loads(event.read_text(encoding="utf-8"))
    assert record["queueWaitMilliseconds"] >= 0
    assert record["completed"]["exitCode"] == 0
    assert "commandFinished" in record
    assert "argv" not in record
    assert "command" not in record


async def cancellation_and_descendants(probe: Probe) -> None:
    """Keep successors queued through admitted cancellation and descendant drain."""
    for mode in ["hold", "descendant"]:
        owner = await probe.start(mode)
        await ready(owner)
        successor = await probe.start()
        pending = await remains_queued(successor)
        if mode == "hold":
            owner.terminate()
            status = await asyncio.wait_for(owner.wait(), 10)
            assert status == 128 + 15
        else:
            await release(owner)
        await asyncio.wait_for(pending, 10)
        await release(successor)


async def probe(runner: str, deadline_runner: str | None) -> None:
    """Exercise the changed lifecycle without changing unrelated work."""
    owned = Probe(runner)
    try:
        await resource_and_serialization(owned)
        await cancellation_and_descendants(owned)
        nested = await asyncio.create_subprocess_exec(
            runner,
            "--feedback",
            runner,
            "--feedback",
            "cat",
            "/proc/self/cgroup",
            stdout=asyncio.subprocess.PIPE,
        )
        output, _ = await nested.communicate()
        assert nested.returncode == 0
        assert b"workstation-task-feedback-" in output
        if deadline_runner:
            # An exact template fixture changes only120s to1s, never the live policy.
            for mode in ["hold", "descendant"]:
                limited = await owned.start(mode, runner=deadline_runner)
                await ready(limited)
                assert await asyncio.wait_for(limited.wait(), 10) != 0, mode
        sys.stdout.write(
            "PASS: feedback caps, serialization, nesting, cancellation, descendants and private timing\n"
        )
    finally:
        await owned.clean()


def child(mode: str) -> None:
    """Expose a readiness pipe and an explicit release gate."""
    if mode == "descendant":
        subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed current interpreter and this source only.
            [sys.executable, __file__, "--child", "hold"],
            stdin=sys.stdin,
        )
        return
    scope = (
        Path("/proc/self/cgroup").read_text(encoding="utf-8").strip().split(":", 2)[2]
    )
    sys.stdout.write(json.dumps({"scope": scope}) + "\n")
    sys.stdout.flush()
    sys.stdin.readline()


if __name__ == "__main__":
    if sys.argv[1:2] == ["--child"]:
        child(sys.argv[2])
    else:
        asyncio.run(probe(sys.argv[1], (sys.argv[2:] or [None])[0]))
