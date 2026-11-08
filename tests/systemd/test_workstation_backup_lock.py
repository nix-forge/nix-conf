"""Run the real backup and bulk lock paths with disposable launcher fixtures."""

import asyncio
import os
import shlex
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[2]


def executable(path: Path, source: str) -> str:
    """Write an executable fixture.

    Returns:
        Its private path.

    """
    # Nix sandboxes expose declared interpreters without /usr/bin/env.
    shebang, separator, body = source.partition("\n")
    if shebang == "#!/usr/bin/env bash":
        bash = shutil.which("bash")
        assert bash is not None, "The fixture requires the declared Bash interpreter"
        source = f"#!{bash}{separator}{body}"
    elif shebang == "#!/usr/bin/env python3":
        source = f"#!{sys.executable}{separator}{body}"
    path.write_text(source, encoding="utf-8")
    path.chmod(0o700)
    return str(path)


def fixtures(work: Path) -> tuple[str, str, str, dict[str, str]]:
    """Render private queue paths and launcher fixtures.

    Returns:
        Bulk and backup commands plus their private environment.

    """
    worker = executable(
        work / "worker",
        "#!/usr/bin/env python3\nimport sys\nprint('ready', flush=True)\nsys.stdin.readline()\n",
    )
    executable(
        work / "systemctl",
        "#!/usr/bin/env bash\nif [[ $* == *background-workload.slice* ]]; then\n  printf 'MemoryHigh=8589934592\nMemoryMax=10737418240\nMemorySwapMax=2147483648\nManagedOOMMemoryPressure=kill\n'\nfi\n",
    )
    executable(
        work / "systemd-run",
        '#!/usr/bin/env bash\nwhile [[ ${1:-} != -- ]]; do shift; done\nshift\nexec "$@"\n',
    )
    (work / "cgroup").write_text("0::/fixture\n")
    lock = shlex.quote(str(work / "shared.lock"))
    runner = (ROOT / "homes/desktop/local/workstation-task.sh").read_text()
    replacements = {
        "@taskEvents@": shlex.join([
            sys.executable,
            str(ROOT / "homes/desktop/local/workstation_task_events.py"),
        ]),
        "@admissionSeconds@": "30",
        "@admissionHealthySeconds@": "0",
        "@admissionPressureLimit@": "100",
        "@growthHealthySeconds@": "1",
        "@growthStepMiB@": "1024",
        "@memoryController@": shlex.join([
            sys.executable,
            str(
                ROOT
                / "modules/home/services/workstation-jobs-assets/workstation_memory.py"
            ),
        ]),
        "@bulkLock@": lock,
        # This fixture verifies lock coordination with tiny fake workers.
        "@bulkMemoryAvailable@": "0",
        "@memoryHigh@": "8589934592",
        "@memoryMax@": "10737418240",
        "@memorySwapMax@": "2147483648",
        "@feedbackMemoryHigh@": "1073741824",
        "@feedbackMemoryMax@": "2147483648",
        "@feedbackSwapMax@": "268435456",
        "@boundedMemoryMinGiB@": "1",
        "@boundedMemoryMaxGiB@": "6",
        "@boundedHighPercent@": "90",
        "@boundedRuntimeSeconds@": "1800",
        "@feedbackReserve@": "1073741824",
        "@feedbackRuntimeSeconds@": "120",
        "@bubblewrap@": '"' + str(work / "bubblewrap") + '"',
        "@waitForCgroup@": "true",
        "/proc/self/cgroup": str(work / "cgroup"),
    }
    executable(
        work / "bubblewrap",
        '#!/usr/bin/env bash\nwhile [[ ${1:-} != -- ]]; do shift; done\nshift\nexec "$@"\n',
    )
    for key, value in replacements.items():
        runner = runner.replace(key, value)
    bulk = executable(work / "bulk", "#!/usr/bin/env bash\n" + runner)
    backup_source = (
        ROOT / "hosts/nixos/desktop/local/storage/scripts/restic-lock-wait.sh"
    ).read_text()
    backup_source = (
        backup_source
        .replace("@flock@", shlex.quote(shutil.which("flock") or "flock"))
        .replace("@bulkLock@", lock)
        .replace("@restic@", shlex.quote(worker))
    )
    backup = executable(work / "backup", "#!/usr/bin/env bash\n" + backup_source)
    environment = os.environ | {
        "PATH": str(work) + os.pathsep + os.environ["PATH"],
        "XDG_RUNTIME_DIR": str(work),
    }
    environment.pop("WORKSTATION_JOB_DIRECTORY", None)
    return bulk, backup, worker, environment


@unittest.skipUnless(
    sys.platform.startswith("linux") and shutil.which("flock"), "Linux flock required"
)
class SharedBulkLockTests(unittest.TestCase):
    """Verify both consumers serialize and a cancelled waiter releases ownership."""

    def test_private_controller_owns_its_scope(self) -> None:
        """An audit controller must bind its scope to itself."""
        asyncio.run(self.controller_binding())

    async def controller_binding(self) -> None:
        """Capture actual launcher arguments for a validated private owner unit."""
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            bulk, _, _, environment = fixtures(work)
            capture = work / "arguments"
            executable(
                work / "systemd-run",
                "#!/usr/bin/env bash\nprintf '%s\\n' \"$@\" > "
                + shlex.quote(str(capture))
                + "\n",
            )
            owner = "workstation-jobs-audit-" + "a" * 32 + ".service"
            environment["WORKSTATION_QUEUE_OWNER_UNIT"] = owner
            process = await asyncio.create_subprocess_exec(
                bulk,
                "true",
                env=environment,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            await asyncio.wait_for(process.communicate(), 5)
            self.assertEqual(process.returncode, 0)
            arguments = capture.read_text().splitlines()
            self.assertIn("--property=BindsTo=" + owner, arguments)
            self.assertIn("--property=After=" + owner, arguments)
            self.assertNotIn("--property=BindsTo=workstation-jobs.service", arguments)

    def test_backup_and_bulk_serialize_in_both_directions(self) -> None:
        """Neither production lock consumer may bypass the other."""
        for first in ("backup", "bulk"):
            with self.subTest(first=first):
                asyncio.run(self.exercise(first, cancel=False))

    def test_cancelled_bulk_waiter_does_not_hold_the_lock(self) -> None:
        """Cancellation of a waiting build must not block the next build."""
        asyncio.run(self.exercise("backup", cancel=True))

    async def exercise(self, first: str, *, cancel: bool) -> None:
        """Render only private paths and fake systemd launch, retaining real flock."""
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            bulk, backup, worker, environment = fixtures(work)
            jobs = []

            async def start(kind: str) -> asyncio.subprocess.Process:
                args = [backup] if kind == "backup" else [bulk, worker]
                job = await asyncio.create_subprocess_exec(
                    *args,
                    env=environment,
                    stdin=asyncio.subprocess.PIPE,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                jobs.append(job)
                return job

            async def ready(job: asyncio.subprocess.Process) -> None:
                assert job.stdout is not None
                self.assertEqual(
                    await asyncio.wait_for(job.stdout.readline(), 5), b"ready\n"
                )

            async def release(job: asyncio.subprocess.Process) -> None:
                assert job.stdin is not None
                job.stdin.write(b"done\n")
                await job.stdin.drain()
                self.assertEqual(await asyncio.wait_for(job.wait(), 5), 0)

            pending = None
            try:
                owner = await start(first)
                await ready(owner)
                other = "bulk" if first == "backup" else "backup"
                waiter = await start(other)
                assert waiter.stdout is not None
                pending = asyncio.create_task(waiter.stdout.readline())
                with self.assertRaises(TimeoutError):
                    await asyncio.wait_for(asyncio.shield(pending), 0.2)
                if cancel:
                    waiter.terminate()
                    self.assertEqual(await asyncio.wait_for(waiter.wait(), 5), 143)
                    await release(owner)
                    successor = await start("bulk")
                    await ready(successor)
                    await release(successor)
                else:
                    await release(owner)
                    self.assertEqual(await asyncio.wait_for(pending, 5), b"ready\n")
                    await release(waiter)
            finally:
                if pending is not None and not pending.done():
                    pending.cancel()
                for job in jobs:
                    if job.returncode is None:
                        job.terminate()
                        await asyncio.wait_for(job.wait(), 5)


if __name__ == "__main__":
    unittest.main()
