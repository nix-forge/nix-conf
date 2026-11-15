"""Controlled native two-lane fixture; production locks and jobs stay untouched."""

import asyncio
import json
import sys

from check_workstation_feedback import ready, release, remains_queued


async def probe(runner: str) -> None:
    """Use a source-identical runner fixture with private test-only lock names."""
    jobs: list[asyncio.subprocess.Process] = []

    async def start(feedback: bool) -> asyncio.subprocess.Process:
        """Start a fixture child.

        Returns:
            Its owned readiness and release process handle.

        """
        job = await asyncio.create_subprocess_exec(
            runner,
            *(["--feedback"] if feedback else []),
            sys.executable,
            __file__.replace(
                "check_workstation_lanes.py", "check_workstation_feedback.py"
            ),
            "--child",
            "hold",
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        jobs.append(job)
        return job

    try:
        bulk = await start(False)
        bulk_info = await ready(bulk)
        feedback = await start(True)
        feedback_pending = await remains_queued(feedback)
        await release(bulk)
        feedback_info = await asyncio.wait_for(feedback_pending, 10)
        feedback_info = json.loads(feedback_info)
        assert feedback_info["scope"] != bulk_info["scope"]
        queued_bulk = await start(False)
        bulk_pending = await remains_queued(queued_bulk)
        queued_feedback = await start(True)
        next_feedback_pending = await remains_queued(queued_feedback)
        await release(feedback)
        pending = {bulk_pending: queued_bulk, next_feedback_pending: queued_feedback}
        done, waiting = await asyncio.wait(
            pending, timeout=10, return_when=asyncio.FIRST_COMPLETED
        )
        assert len(done) == 1
        winner = done.pop()
        assert winner.result()
        await release(pending[winner])
        loser = waiting.pop()
        assert await asyncio.wait_for(loser, 10)
        await release(pending[loser])
        sys.stdout.write(
            "PASS: cross-lane progress with one shared execution reservation\n"
        )
    finally:
        for job in jobs:
            if job.returncode is None:
                job.terminate()
                await asyncio.wait_for(job.wait(), 10)


if __name__ == "__main__":
    asyncio.run(probe(sys.argv[1]))
