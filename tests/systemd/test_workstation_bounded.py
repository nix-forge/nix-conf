"""Exercise bounded admission and real scope isolation with tiny payloads."""

import asyncio
import json
import os
import platform
import re
import shlex
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Run only fixed probe commands.
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[2]
RUNNER = (
    Path(sys.argv.pop(1))
    if __name__ == "__main__" and len(sys.argv) > 1 and not sys.argv[1].startswith("-")
    else None
)


@unittest.skipUnless(
    sys.platform.startswith("linux")
    and (Path(os.environ.get("XDG_RUNTIME_DIR", "/nonexistent")) / "bus").exists(),
    "native Linux user-manager session required",
)
class BoundedTests(unittest.TestCase):
    """Use private queues, keeping the production scope and namespace behavior."""

    @classmethod
    def setUpClass(cls) -> None:
        """Render the maintained source with private queue paths and real helpers."""
        cls.directory = tempfile.TemporaryDirectory()
        cls.work = Path(cls.directory.name)
        runner_path = RUNNER or shutil.which("workstation-task")
        assert runner_path is not None, "workstation-task is required"
        installed = Path(runner_path).read_text(encoding="utf-8")
        wait_helper = re.search(
            r"(/nix/store/[^ ]+-wait-workstation-cgroup)", installed
        )
        assert wait_helper is not None, "installed cgroup observer is required"
        source = (
            installed
            if RUNNER
            else (ROOT / "homes/desktop/local/workstation-task.sh").read_text(
                encoding="utf-8"
            )
        )
        for key, value in {
            "taskEvents": shlex.quote(str(shutil.which("python3")))
            + " "
            + shlex.quote(str(ROOT / "homes/desktop/local/workstation_task_events.py")),
            "diskAdmission": "true",
            "admissionSeconds": "1",
            "admissionHealthySeconds": "0",
            "admissionPressureLimit": "100",
            "growthHealthySeconds": "1",
            "growthStepMiB": "1024",
            "memoryController": shlex.join([
                sys.executable,
                str(
                    ROOT
                    / "modules/home/services/workstation-jobs-assets/workstation_memory.py"
                ),
            ]),
            "bulkLock": shlex.quote(str(cls.work / "shared.lock")),
            "bulkMemoryAvailable": "12884901888",
            "boundedReserve": "2147483648",
            "bubblewrap": shlex.quote(shutil.which("bwrap") or "bwrap"),
            "memoryHigh": "8589934592",
            "memoryMax": "10737418240",
            "memorySwapMax": "2147483648",
            "feedbackMemoryHigh": "1879048192",
            "feedbackMemoryMax": "2147483648",
            "feedbackSwapMax": "268435456",
            "boundedMemoryMinGiB": "1",
            "boundedMemoryMaxGiB": "6",
            "boundedHighPercent": "90",
            "boundedRuntimeSeconds": "1800",
            "feedbackReserve": "1073741824",
            "feedbackRuntimeSeconds": "120",
            "waitForCgroup": wait_helper[1],
        }.items():
            source = source.replace("@" + key + "@", value)
        source = re.sub(
            r"^admission_timeout=\d+$",
            "admission_timeout=10",
            source,
            flags=re.MULTILINE,
        )
        source = re.sub(r"--healthy-seconds \d+", "--healthy-seconds 0", source)
        assert not re.search(r"@[a-zA-Z]+@", source)
        source = source.replace(
            "workstation-background.lock", "bounded-probe-bulk.lock"
        )
        source = source.replace(
            "workstation-feedback.lock", "bounded-probe-feedback.lock"
        )
        source = source.replace(
            "/run/workstation-workloads/bulk.lock", str(cls.work / "shared.lock")
        )
        cls.source = source

    @classmethod
    def tearDownClass(cls) -> None:
        """Remove only this probe's private fixture files."""
        cls.directory.cleanup()

    def runner(self, available: str | None = None, deadline: str | None = None) -> str:
        """Render private admission/deadline fixtures.

        Returns:
            The executable fixture path.

        """
        source = self.source
        if available is not None:
            meminfo = self.work / "meminfo"
            meminfo.write_text(
                f"MemAvailable: {int(available) // 1024 if available.isdigit() else available} kB\n",
                encoding="utf-8",
            )
            source, count = re.subn(
                r"--meminfo (?:'[^']*'|\"[^\"]*\"|[^\s]+)(?= --root )",
                "--meminfo " + shlex.quote(str(meminfo)),
                source,
            )
            assert count == 1, "The real controller must use the capacity fixture"
        if deadline:
            source = source.replace("RuntimeMaxSec=1800s", "RuntimeMaxSec=" + deadline)
        path = self.work / "runner"
        bash = shutil.which("bash")
        assert bash is not None, "The fixture requires the declared Bash interpreter"
        path.write_text(f"#!{bash}\n" + source, encoding="utf-8")
        path.chmod(0o700)
        return str(path)

    @staticmethod
    def run_job(runner: str, *args: str) -> subprocess.CompletedProcess[str]:
        """Run a fixed tiny probe invocation.

        Returns:
            Its actual exit status and output.

        """
        return subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed local fixture argv.
            [runner, *args],
            capture_output=True,
            text=True,
            timeout=25,
            check=False,
        )

    def test_budget_admission_and_no_payload_on_refusal(self) -> None:
        """Admit the smaller scope below 12 GiB; reject insufficient or invalid reads."""
        marker = self.work / "must-not-run"
        for available in ["", "invalid", "3221225471"]:
            result = self.run_job(
                self.runner(available),
                "--admission-timeout",
                "2",
                "--bounded-memory",
                "1",
                "touch",
                str(marker),
            )
            self.assertEqual(result.returncode, 124, result.stderr)
            self.assertFalse(marker.exists())
        result = self.run_job(
            self.runner("3221225472"),
            "--bounded-memory",
            "1",
            "printf",
            "%s",
            "admitted",
        )
        self.assertEqual(
            (result.returncode, result.stdout), (0, "admitted"), result.stderr
        )
        result = self.run_job(
            self.runner("3221225472"), "--admission-timeout", "2", "touch", str(marker)
        )
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertFalse(marker.exists())

    def test_real_caps_and_daemon_isolation(self) -> None:
        """Prove real cgroup limits, hidden daemon socket, and read-only evaluation."""
        child = self.work / "inspect.py"
        child.write_text(
            "import json,os\nfrom pathlib import Path\n"
            "with open('/dev/null','wb') as sink:sink.write(b'probe')\n"
            "g=Path('/sys/fs/cgroup')/Path('/proc/self/cgroup').read_text().strip().split('::')[1].lstrip('/')\n"
            "print(json.dumps({'max':(g/'memory.max').read_text().strip(),"
            "'high':(g/'memory.high').read_text().strip(),"
            "'swap':(g/'memory.swap.max').read_text().strip(),"
            "'daemonVisible':Path('/nix/var/nix/daemon-socket/socket').exists(),"
            "'cwd':os.getcwd()}))\n",
            encoding="utf-8",
        )
        for flags, maximum, high, swap in [
            (["--bounded-memory", "1"], "1073741824", "966365184", "0"),
            (["--feedback"], "2147483648", "1879048192", "268435456"),
        ]:
            with self.subTest(profile=flags):
                result = self.run_job(self.runner(), *flags, sys.executable, str(child))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    json.loads(result.stdout),
                    {
                        "max": maximum,
                        "high": high,
                        "swap": swap,
                        "daemonVisible": False,
                        "cwd": str(Path.cwd()),
                    },
                )
        ping = self.run_job(
            self.runner(),
            "--bounded-memory",
            "1",
            "nix",
            "store",
            "ping",
            "--store",
            "daemon",
        )
        self.assertNotEqual(ping.returncode, 0)
        evaluation = self.run_job(
            self.runner(),
            "--bounded-memory",
            "1",
            "nix",
            "--extra-experimental-features",
            "read-only-local-store",
            "eval",
            "--store",
            "local?read-only=true",
            "--expr",
            "1 + 1",
        )
        self.assertEqual(
            (evaluation.returncode, evaluation.stdout.strip()),
            (0, "2"),
            evaluation.stderr,
        )

    def test_failure_deadline_and_budget_validation(self) -> None:
        """Preserve failures and reject invalid budgets and timed-out descendants."""
        for budget in ["0", "99999999", "-1", "4G", "1;true"]:
            result = self.run_job(self.runner(), "--bounded-memory", budget, "true")
            self.assertEqual(result.returncode, 2, result.stderr)
        failure = self.run_job(
            self.runner(),
            "--bounded-memory",
            "1",
            "bash",
            "-c",
            "exit 23",
        )
        self.assertEqual(failure.returncode, 23)
        expired = self.run_job(
            self.runner(deadline="1s"),
            "--bounded-memory",
            "1",
            "bash",
            "-c",
            "sleep 3 & exit 0",
        )
        self.assertNotEqual(expired.returncode, 0, expired.stderr)

    def test_private_nix_builder_stays_inside_the_budget(self) -> None:
        """Build a tiny real derivation without the shared daemon or remote builders."""
        store = self.work / "private-store"
        bash_path = shutil.which("bash")
        assert bash_path is not None, "Bash is required"
        bash = Path(bash_path).resolve().parent.parent
        uri = "local?root=" + str(store)
        expression = (
            'derivation { name = "bounded-local-proof"; system = '
            + json.dumps(platform.machine() + "-linux")
            + "; builder = (builtins.storePath "
            + json.dumps(str(bash))
            + ') + "/bin/bash"; args = [ "-c" "echo bounded-proof > $out" ]; }'
        )
        command = (
            "set -euo pipefail\n"
            + shlex.join([
                "nix",
                "--extra-experimental-features",
                "read-only-local-store",
                "copy",
                "--from",
                "local?read-only=true",
                "--to",
                uri,
                str(bash),
            ])
            + "\n"
            + shlex.join([
                "nix",
                "build",
                "--impure",
                "--store",
                uri,
                "--option",
                "build-users-group",
                "",
                "--option",
                "builders",
                "",
                "--no-link",
                "--print-out-paths",
                "--expr",
                expression,
            ])
        )
        result = self.run_job(
            self.runner(), "--bounded-memory", "1", "bash", "-c", command
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        output = store / result.stdout.strip().lstrip("/")
        self.assertEqual(output.read_text(encoding="utf-8"), "bounded-proof\n")

    def test_bounded_work_serializes_with_both_lanes(self) -> None:
        """Keep both successors queued until the bounded scope releases its locks."""
        asyncio.run(self.exercise_locks())

    async def exercise_locks(self) -> None:
        """Own and clean up tiny pipe-gated scopes using only private queue names."""
        runner = self.runner("34359738368")
        jobs = []
        try:
            for flags in [["--bounded-memory", "1"], ["--feedback"], []]:
                job = await asyncio.create_subprocess_exec(
                    runner,
                    *flags,
                    sys.executable,
                    "-c",
                    "import sys;print('ready',flush=True);sys.stdin.readline()",
                    stdin=asyncio.subprocess.PIPE,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                jobs.append(job)
                assert job.stdout is not None
                assert job.stdin is not None
                if len(jobs) == 1:
                    self.assertEqual(
                        await asyncio.wait_for(job.stdout.readline(), 10), b"ready\n"
                    )
            pending = []
            for job in jobs[1:]:
                assert job.stdout is not None
                pending.append(asyncio.create_task(job.stdout.readline()))
            for read in pending:
                with self.assertRaises(TimeoutError):
                    await asyncio.wait_for(asyncio.shield(read), 0.15)
            assert jobs[0].stdin is not None
            jobs[0].stdin.write(b"release\n")
            await jobs[0].stdin.drain()
            self.assertEqual(await asyncio.wait_for(jobs[0].wait(), 10), 0)
            contenders = dict(zip(pending, jobs[1:], strict=True))
            while contenders:
                done, _ = await asyncio.wait(
                    contenders, timeout=10, return_when=asyncio.FIRST_COMPLETED
                )
                self.assertEqual(len(done), 1)
                read = done.pop()
                job = contenders.pop(read)
                if not read.result():
                    code = await asyncio.wait_for(job.wait(), 5)
                    assert job.stderr is not None
                    error = (await job.stderr.read()).decode()
                    self.fail(f"Queued runner exited {code} before readiness: {error}")
                self.assertEqual(read.result(), b"ready\n")
                assert job.stdin is not None
                job.stdin.write(b"release\n")
                await job.stdin.drain()
                self.assertEqual(await asyncio.wait_for(job.wait(), 10), 0)
        finally:
            for job in jobs:
                if job.returncode is None:
                    job.terminate()
                    await asyncio.wait_for(job.wait(), 10)


if __name__ == "__main__":
    unittest.main()
