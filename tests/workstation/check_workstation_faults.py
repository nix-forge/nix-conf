"""Audit native queue recovery and OOM in UUID-owned disposable Linux units.

Run outside workload allocations through codex-task. Private receipts remain on
disk. Only this coordinator's controller, slice, and submitted units are stopped.
"""
# Runtime JSON is an external contract; commands use explicit immutable/private argv.
# ruff: file-ignore[magic-value-comparison, print, too-many-locals]

import argparse
import asyncio
import hashlib
import json
import os
import sys
import time
import uuid
from pathlib import Path
from typing import Any

MIB = 1024**2
Json = dict[str, Any]


def require(condition: bool, message: str) -> None:
    """Fail a native contract without claiming the remaining cases passed.

    Raises:
        RuntimeError: The observed native contract differs from the requirement.

    """
    if not condition:
        raise RuntimeError(message)


def read(path: Path) -> Json:
    """Read private JSON evidence.

    Returns:
        Its parsed object.

    """
    return json.loads(path.read_text(encoding="utf-8"))


def save(path: Path, value: Json) -> None:
    """Retain compact private evidence, including failed attempts."""
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def oom_count() -> int:
    """Read the host counter without interpreting an expected scoped OOM as healthy.

    Returns:
        The current kernel OOM kill counter.

    """
    return int(
        dict(
            line.split()
            for line in Path("/proc/vmstat").read_text(encoding="utf-8").splitlines()
        )["oom_kill"]
    )


class Audit:
    """Own bounded commands and one uniquely named controller lifecycle."""

    def __init__(self, client: Path, base: Json, root: Path) -> None:
        """Select UUID-only unit identities before creating any native resources."""
        self.client = str(client.resolve(strict=True))
        self.base = base
        self.root = root
        self.nonce = uuid.uuid4().hex
        self.owner = f"workstation-jobs-audit-{self.nonce}.service"
        self.slice = f"workstation-jobs-audit-{self.nonce}-workload.slice"
        self.jobs: list[str] = []
        self.config = ""
        self.pueue_config = ""
        self.slice_file = (
            Path(os.environ["XDG_RUNTIME_DIR"]) / "systemd/user" / self.slice
        )
        self.slice_created = False
        self.evidence: Json = {
            "passed": False,
            "ownerUnit": self.owner,
            "workloadSlice": self.slice,
            "jobs": {},
            "oomBefore": oom_count(),
        }

    @staticmethod
    async def command(
        *arguments: str, expected: int | None = 0, seconds: int = 20
    ) -> tuple[int, str]:
        """Run a bounded observer or an explicitly owned native action.

        Returns:
            Actual exit status and stdout.

        Raises:
            TimeoutError: The bounded observer exceeded its deadline.
            RuntimeError: The native command did not produce an expected terminal status.

        """
        process = await asyncio.create_subprocess_exec(
            *arguments, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
        try:
            stdout, stderr = await asyncio.wait_for(process.communicate(), seconds)
        except TimeoutError:
            process.kill()
            await asyncio.wait_for(process.communicate(), 5)
            raise
        code = process.returncode
        if code is None:
            message = "Command observer has no terminal status"
            raise RuntimeError(message)
        if expected is not None:
            require(
                code == expected,
                f"Unexpected exit {code}: {stdout.decode()} {stderr.decode()}",
            )
        return int(code), stdout.decode().strip()

    async def ctl(self, *arguments: str, expected: int | None = 0) -> tuple[int, str]:
        """Call the user manager using explicit UUID-owned unit arguments.

        Returns:
            Exit status and stdout.

        """
        return await self.command(
            self.base["systemctl"], "--user", *arguments, expected=expected
        )

    async def cli(
        self, *arguments: str, expected: int | None = 0, seconds: int = 45
    ) -> tuple[int, str]:
        """Call only the private-config adapter.

        Returns:
            Exit status and stdout.

        """
        return await self.command(
            self.client,
            "--config",
            self.config,
            *arguments,
            expected=expected,
            seconds=seconds,
        )

    async def native(self, *arguments: str) -> str:
        """Call only the private Unix-socket Pueue instance.

        Returns:
            Native stdout.

        """
        return (
            await self.command(self.base["pueue"], "-c", self.pueue_config, *arguments)
        )[1]

    async def prepare(self) -> None:
        """Add immutable private configurations and declare the bounded private slice."""
        pueue = self.root / "pueue.json"
        save(
            pueue,
            {
                "shared": {
                    "pueue_directory": str(self.root / "state/pueue"),
                    "runtime_directory": str(self.root / "runtime"),
                    "pid_path": str(self.root / "pueue.pid"),
                    "unix_socket_path": str(self.root / "queue.socket"),
                    "use_unix_socket": True,
                },
                "daemon": {"default_parallel_tasks": 1},
            },
        )
        self.pueue_config = (
            await self.command(self.base["nixStore"], "--add", str(pueue))
        )[1]
        cfg = self.base | {
            "stateDirectory": str(self.root / "state"),
            "ownerUnit": self.owner,
            "workloadSlice": self.slice,
            "pueueConfig": self.pueue_config,
            "reserveMiB": 512,
            "profiles": {
                "bounded": {
                    "backend": "systemd",
                    "memoryMiB": 64,
                    "minimumMiB": 64,
                    "maximumMiB": 64,
                    "maximumSeconds": 30,
                }
            },
        }
        private = self.root / "config.json"
        save(private, cfg)
        self.config = (
            await self.command(self.base["nixStore"], "--add", str(private))
        )[1]
        self.slice_file.parent.mkdir(parents=True, exist_ok=True)
        require(not self.slice_file.exists(), "UUID slice already exists")
        self.slice_file.write_text(
            "[Unit]\nDescription=Disposable finite queue fault audit\n[Slice]\nMemoryMax=256M\nMemorySwapMax=0\n",
            encoding="utf-8",
        )
        self.slice_created = True
        await self.ctl("daemon-reload")
        await self.ctl("start", self.slice)
        await self.start()

    async def start(self) -> None:
        """Start or recreate only the audit's private notify controller."""
        _, loaded = await self.ctl(
            "show", self.owner, "-p", "LoadState", "--value", expected=None
        )
        if loaded == "loaded":
            await self.ctl("start", self.owner)
        else:
            await self.command(
                self.base["systemdRun"],
                "--user",
                "--unit",
                self.owner,
                "--property=Type=notify",
                "--property=NotifyAccess=main",
                "--property=KillMode=control-group",
                "--property=MemoryMax=128M",
                "--property=MemorySwapMax=0",
                "--property=Slice=" + self.slice,
                "--property=RuntimeMaxSec=240",
                "--",
                self.client,
                "--config",
                self.config,
                "serve",
            )
        await self.cli("doctor")

    async def submit(self, key: str, code: str, *arguments: str) -> str:
        """Submit one tiny finite private job and retain its stable identity.

        Returns:
            The adapter's stable UUID.

        """
        _, identifier = await self.cli(
            "submit",
            "--owner",
            "native-fault-audit-" + self.nonce,
            "--key",
            key,
            "--source",
            "sha256:" + hashlib.sha256(code.encode()).hexdigest(),
            "--cwd",
            str(self.root),
            "--profile",
            "bounded",
            "--memory-mib",
            "64",
            "--timeout",
            "30",
            "--",
            sys.executable,
            "-c",
            code,
            *arguments,
        )
        require(
            len(identifier) == 32 and all(c in "0123456789abcdef" for c in identifier),
            "Invalid job identity",
        )
        self.jobs.append(identifier)
        return identifier

    def directory(self, identifier: str) -> Path:
        """Resolve only a previously submitted private job directory.

        Returns:
            The owned receipt directory.

        """
        require(identifier in self.jobs, "Unowned job")
        return self.root / "state/jobs" / identifier

    async def status(self, identifier: str) -> Json:
        """Read one private job's current native status and receipt.

        Returns:
            Compact adapter job metadata.

        """
        record = json.loads((await self.cli("status", identifier))[1])["jobs"][0]
        self.evidence["jobs"][identifier] = record
        return record

    async def wait(self, identifier: str, success: bool) -> Json:
        """Require a finite terminal result and drained owned execution.

        Returns:
            Terminal job metadata.

        """
        await self.cli(
            "wait", "--timeout", "40", identifier, expected=0 if success else 1
        )
        record = await self.status(identifier)
        result = record["nativeStatus"].get("Done", {}).get("result")
        require((result == "Success") == success, "Unexpected native terminal result")
        require(record["receipt"]["drained"] is True, "Execution is not proven drained")
        return record

    async def pause_case(self) -> None:
        """Preserve a deliberate queue pause and an unclaimed recipe across restart."""
        await self.native("pause", "--group", "bounded", "--wait")
        marker = self.root / "paused-marker"
        identifier = await self.submit(
            "manual-pause",
            "import sys; open(sys.argv[1], 'a').write('once\\n')",
            str(marker),
        )
        await self.ctl("restart", self.owner)
        doctor = json.loads((await self.cli("doctor"))[1])
        job = await self.status(identifier)
        require(
            doctor["groups"]["bounded"]["status"] == "Paused", "Manual pause was lost"
        )
        require(
            "Queued" in job["nativeStatus"]
            and not marker.exists()
            and not (self.directory(identifier) / "execution.claim").exists(),
            "Paused job was executed or claimed",
        )
        await self.native("start", "--group", "bounded")
        await self.wait(identifier, True)
        require(
            marker.read_text() == "once\n",
            "Paused payload did not execute exactly once",
        )
        self.evidence["pause"] = {
            "id": identifier,
            "pausePreserved": True,
            "unclaimedUntilResume": True,
        }

    async def oom_case(self) -> None:
        """Trigger an expected private cgroup OOM and verify kernel stop accounting."""
        proof = self.root / "oom-limits.json"
        ready = self.root / "oom-ready.fifo"
        release = self.root / "oom-release.fifo"
        for fifo in (ready, release):
            os.mkfifo(fifo, 0o600)
        ready_fd = os.open(ready, os.O_RDWR | os.O_NONBLOCK)
        release_fd = os.open(release, os.O_RDWR | os.O_NONBLOCK)
        loop = asyncio.get_running_loop()
        readiness = loop.create_future()

        def notified() -> None:
            if os.read(ready_fd, 4096) and not readiness.done():
                readiness.set_result(True)

        loop.add_reader(ready_fd, notified)
        code = """import json,pathlib,subprocess,sys
group=pathlib.Path('/proc/self/cgroup').read_text().split('::',1)[1].strip()
root=pathlib.Path('/sys/fs/cgroup')/group.lstrip('/')
with open(sys.argv[2], 'w') as stream: stream.write('ready\\n'); stream.flush()
with open(sys.argv[3]) as stream: stream.read(1)
pathlib.Path(sys.argv[1]).write_text(json.dumps({name:(root/name).read_text().strip() for name in ['memory.max','memory.swap.max','memory.oom.group']}))
child="import time; data=bytearray(50*1024**2); data[::4096]=b'x'*len(data[::4096]); time.sleep(25)"
children=[subprocess.Popen([sys.executable,'-c',child]) for _ in range(2)]
for process in children: process.wait()
"""
        try:
            identifier = await self.submit(
                "expected-oom", code, str(proof), str(ready), str(release)
            )
            await asyncio.wait_for(readiness, 10)
            # Only this disposable unit: bypass reclaim throttling to test its
            # unchanged 64 MiB hard ceiling within the finite test deadline.
            await self.ctl(
                "set-property",
                "--runtime",
                "workstation-job-" + identifier + ".service",
                "MemoryHigh=64M",
            )
            os.write(release_fd, b"x")
            record = await self.wait(identifier, False)
        finally:
            loop.remove_reader(ready_fd)
            os.close(ready_fd)
            os.close(release_fd)
        limits = read(proof)
        require(
            limits
            == {
                "memory.max": str(64 * MIB),
                "memory.swap.max": "0",
                "memory.oom.group": "1",
            },
            "Actual OOM limits differ from reviewed budget",
        )
        native = record["receipt"]["nativeResources"]
        require(
            native["measurement"] == "kernel-at-unit-stop"
            and native["MemoryPeak"] > 0
            and native["memoryEvents"].get("oom_kill", 0) > 0,
            "Expected kernel OOM evidence missing",
        )
        require(
            not (Path("/sys/fs/cgroup") / native["controlGroup"].lstrip("/")).exists(),
            "OOM job cgroup remains",
        )
        self.evidence["expectedOom"] = {
            "id": identifier,
            "limits": limits,
            "nativeResources": native,
            "hostOomAfter": oom_count(),
        }
        successor = await self.submit("after-oom", "print('healthy-after-oom')")
        await self.wait(successor, True)

    async def interruption_case(self) -> None:
        """Kill only the private controller and require explicit no-replay reconciliation."""
        fifo = self.root / "ready.fifo"
        os.mkfifo(fifo, 0o600)
        descriptor = os.open(fifo, os.O_RDWR | os.O_NONBLOCK)
        loop = asyncio.get_running_loop()
        readiness = loop.create_future()

        def notified() -> None:
            data = os.read(descriptor, 4096)
            if data and not readiness.done():
                readiness.set_result(data)

        loop.add_reader(descriptor, notified)
        try:
            marker = self.root / "interrupted-marker"
            code = "import pathlib,sys,time; pathlib.Path(sys.argv[2]).open('a').write('once\\n'); stream=open(sys.argv[1],'w'); stream.write('ready\\n'); stream.flush(); time.sleep(30)"
            old = await self.submit("interrupted", code, str(fifo), str(marker))
            require(
                await asyncio.wait_for(readiness, 10) == b"ready\n",
                "Payload readiness missing",
            )
            claim = self.directory(old) / "execution.claim"
            claim_before = claim.read_bytes()
            successor_marker = self.root / "successor-marker"
            successor = await self.submit(
                "queued-successor",
                "import pathlib,sys; pathlib.Path(sys.argv[1]).open('a').write('once\\n')",
                str(successor_marker),
            )
            queued = await self.status(successor)
            require("Queued" in queued["nativeStatus"], "Successor was not queued")
            await self.ctl("kill", "--signal=SIGKILL", "--kill-whom=all", self.owner)
            await self.ctl("stop", self.owner)
            await self.ctl("stop", "workstation-job-" + old + ".service", expected=None)
            original_result = (self.directory(old) / "result.json").read_bytes()
            await self.start()
            old_status = await self.status(old)
            require(
                "Done" in old_status["nativeStatus"]
                and old_status["nativeStatus"]["Done"]["result"] != "Success",
                "Interrupted job was not preserved as failed",
            )
            doctor = json.loads((await self.cli("doctor"))[1])
            require(
                doctor["recovery"]["needsReconciliation"] is True,
                "Recovery did not require reconciliation",
            )
            require(
                not successor_marker.exists()
                and not (self.directory(successor) / "execution.claim").exists(),
                "Queued successor executed before reconciliation",
            )
            refused, _ = await self.cli(
                "resume-queued", "--acknowledge-interrupted", expected=None
            )
            require(refused != 0, "Unreconciled interrupted job allowed resume")
            _, reconciliation = await self.cli(
                "reconcile", old, "--acknowledge-interrupted"
            )
            require(
                json.loads(reconciliation)["drained"] is True,
                "Reconciliation lacks drain proof",
            )
            require(
                claim.read_bytes() == claim_before
                and (self.directory(old) / "result.json").read_bytes()
                == original_result,
                "Reconciliation rewrote original claim or failure",
            )
            await self.cli("resume-queued", "--acknowledge-interrupted")
            await self.wait(successor, True)
            require(
                marker.read_text() == "once\n"
                and successor_marker.read_text() == "once\n"
                and claim.read_bytes() == claim_before,
                "Interrupted or successor payload replayed",
            )
            self.evidence["interruption"] = {
                "id": old,
                "successor": successor,
                "claimUnchanged": True,
                "failedResultUnchanged": True,
                "resumeRefusedUntilReconcile": True,
                "reconciliation": json.loads(reconciliation),
            }
        finally:
            loop.remove_reader(descriptor)
            os.close(descriptor)

    async def cleanup(self) -> None:
        """Stop only UUID-owned units and retain all private evidence files."""
        errors = []
        for unit in [
            self.owner,
            *("workstation-job-" + identifier + ".service" for identifier in self.jobs),
            self.slice,
            self.owner.removesuffix(".service") + ".slice",
        ]:
            try:
                await self.ctl("stop", unit, expected=None)
                code, active = await self.ctl("is-active", unit, expected=None)
                require(
                    code != 0
                    and active not in {"active", "activating", "deactivating"},
                    "Private unit did not drain: " + unit,
                )
                await self.ctl("reset-failed", unit, expected=None)
            except (OSError, RuntimeError, TimeoutError) as error:
                errors.append(str(error))
        try:
            if self.slice_created:
                self.slice_file.unlink(missing_ok=True)
            await self.ctl("daemon-reload")
        except (OSError, RuntimeError, TimeoutError) as error:
            errors.append(str(error))
        if errors:
            self.evidence["passed"] = False
        self.evidence["cleanupErrors"] = errors
        self.evidence["oomAfter"] = oom_count()
        save(self.root / "verification.json", self.evidence)
        require(not errors, "Private-unit cleanup did not complete")


async def run(args: argparse.Namespace) -> None:
    """Exercise finite private faults and preserve results on every exit.

    Raises:
        OSError: Private evidence or native resources could not be accessed.
        RuntimeError: A required native contract failed.
        TimeoutError: A bounded observer did not finish.
        KeyError: Required native receipt metadata is absent.
        ValueError: Private JSON or numeric evidence cannot be decoded.

    """
    require(sys.platform.startswith("linux"), "Native fault audit is Linux-only")
    require(
        not os.environ.get("WORKSTATION_JOB_ID"),
        "Run this coordinator outside allocations",
    )
    require(
        not args.state.exists() or not any(args.state.iterdir()),
        "Use a fresh empty private state directory",
    )
    os.umask(0o077)
    args.state.mkdir(mode=0o700, parents=True, exist_ok=True)
    audit = Audit(args.client, read(args.base_config), args.state.resolve())
    try:
        await audit.prepare()
        await audit.pause_case()
        await audit.oom_case()
        await audit.interruption_case()
        audit.evidence.update(passed=True, completed=time.time())
    except (OSError, RuntimeError, TimeoutError, KeyError, ValueError) as error:
        audit.evidence["error"] = str(error)
        raise
    finally:
        await audit.cleanup()
    print(
        json.dumps({
            "passed": True,
            "receipt": str(audit.root / "verification.json"),
            "jobs": audit.jobs,
        })
    )


def main() -> None:
    """Parse the exact client and base configuration selected for this audit."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("client", type=Path)
    parser.add_argument("--base-config", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    main()
