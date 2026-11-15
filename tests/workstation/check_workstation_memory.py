"""Check actual upward-only memory grants in one disposable Linux service.

Run this coordinator outside workload allocations through codex-task. It owns
only its UUID service and uses less than 64 MiB, under the existing aggregate.
"""
# ruff: file-ignore[magic-value-comparison]

import argparse
import asyncio
import contextlib
import json
import os
import signal
import sys
import tempfile
import uuid
from pathlib import Path


async def check(controller: Path) -> None:
    """Require a manager-applied grant and preserve complete payload/drain evidence."""
    unit = "workstation-memory-probe-" + uuid.uuid4().hex + ".service"
    with tempfile.TemporaryDirectory(prefix="workstation-memory-probe-") as work:
        receipt = Path(work) / "allocation.json"
        receipt.write_text(
            json.dumps({"grantMiB": 64, "maximumMiB": 128, "changes": []}),
            encoding="utf-8",
        )
        program = (
            "import json,sys;from pathlib import Path;"
            'payload=bytearray(47*1024*1024);payload[::4096]=b"x"*(len(payload)//4096);'
            "print('ready',flush=True);sys.stdin.readline();"
            "root=Path('/sys/fs/cgroup')/Path('/proc/self/cgroup').read_text().strip().split('::')[1].lstrip('/');"
            "print(json.dumps({key:(root/key).read_text().strip() for key in ['memory.max','memory.high','memory.swap.max']}),flush=True)"
        )
        process = await asyncio.create_subprocess_exec(
            "systemd-run",
            "--user",
            "--quiet",
            "--wait",
            "--pipe",
            "--unit",
            unit,
            "--slice",
            "background-workload.slice",
            "-p",
            "MemoryMax=64M",
            "-p",
            "MemoryHigh=60397977",
            "-p",
            "MemorySwapMax=0",
            "-p",
            "OOMPolicy=kill",
            "-p",
            "RuntimeMaxSec=30",
            sys.executable,
            "-c",
            program,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        growth = None
        try:  # ruff: ignore[too-many-statements-in-try-clause] - one owned native probe lifecycle
            assert process.stdout is not None
            assert process.stdin is not None
            assert await asyncio.wait_for(process.stdout.readline(), 10) == b"ready\n"
            growth = await asyncio.create_subprocess_exec(
                sys.executable,
                str(controller),
                "grow",
                "--receipt",
                str(receipt),
                "--reserve",
                "2048",
                "--quantum",
                "1",
                "--step",
                "64",
                "--growth-seconds",
                "0.1",
                "--unit",
                unit,
            )
            assert await asyncio.wait_for(growth.wait(), 15) == 0
            allocation = json.loads(receipt.read_text(encoding="utf-8"))
            assert allocation["grantMiB"] == 128
            assert len(allocation["changes"]) == 1
            assert allocation["changes"][0]["fromMiB"] == 64
            process.stdin.write(b"inspect\n")
            await process.stdin.drain()
            process.stdin.close()
            observed = json.loads(await asyncio.wait_for(process.stdout.readline(), 5))
            assert int(observed["memory.max"]) == 128 * 1024**2
            assert int(observed["memory.high"]) == (
                128 * 1024**2 * 90 // 100
            ) // os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PAGE_SIZE")
            assert observed["memory.swap.max"] == "0"
            assert await asyncio.wait_for(process.wait(), 5) == 0
            # systemd-run --wait is terminal; explicitly stop and verify the
            # recorded cgroup is absent or recursively unpopulated below.
            response = await asyncio.create_subprocess_exec(
                "systemctl",
                "--user",
                "show",
                unit,
                "-p",
                "ControlGroup",
                "--value",
                stdout=asyncio.subprocess.PIPE,
            )
            output, _ = await response.communicate()
            group = output.decode().strip()
            if group:
                events = Path("/sys/fs/cgroup") / group.lstrip("/") / "cgroup.events"
                assert not events.exists() or "populated 0" in events.read_text(
                    encoding="utf-8"
                )
            sys.stdout.write(
                json.dumps({
                    "grantMiB": 128,
                    "changes": 1,
                    "payloadExit": 0,
                    "drained": True,
                })
                + "\n"
            )
        except BaseException as error:
            error.add_note(receipt.read_text(encoding="utf-8"))
            raise
        finally:
            if growth is not None and growth.returncode is None:
                growth.terminate()
                await growth.wait()
            stopper = await asyncio.create_subprocess_exec(
                "systemctl", "--user", "stop", unit
            )
            await stopper.wait()
            if process.returncode is None:
                with contextlib.suppress(ProcessLookupError):
                    process.send_signal(signal.SIGTERM)
                await process.wait()
            reset = await asyncio.create_subprocess_exec(
                "systemctl",
                "--user",
                "reset-failed",
                unit,
                stderr=asyncio.subprocess.DEVNULL,
            )
            await reset.wait()


def main() -> None:
    """Run the disposable native probe with its explicit controller source."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("controller", type=Path)
    args = parser.parse_args()
    asyncio.run(check(args.controller.resolve()))


if __name__ == "__main__":
    main()
