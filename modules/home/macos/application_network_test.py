"""Bounded TCP/Network.framework acceptance from the protected GUI application's command runner."""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import socket
import subprocess  # ruff: ignore[suspicious-subprocess-import]
import sys
import threading
import time
from pathlib import Path
from typing import NoReturn

PS_FIELD_COUNT = 2
MAX_PORT = 65535


def fail(message: str) -> NoReturn:
    """Reject invalid acceptance input.

    Raises:
        ValueError: With the input failure.

    """
    raise ValueError(message)


def run(args: list[str]) -> subprocess.CompletedProcess:
    """Run a child with an overall timeout and captured output.

    Returns:
        The validated operation result.

    """
    return subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Explicit argument lists, no shell.
        args, capture_output=True, text=True, timeout=35, check=False
    )


def ancestry(app: Path) -> list[dict]:
    """Reject SSH/Terminal/launchd origins; record the GUI ancestor for audit.

    This is ancestry evidence, not an independent kernel responsibility query.
    Kernel responsibility can be confirmed by an operator using launchctl procinfo.

    Returns:
        The validated operation result.

    """
    parents = []
    pid = os.getpid()
    expected = str(app / "Contents/MacOS/ChatGPT")
    for _ in range(32):
        output = run(["/bin/ps", "-p", str(pid), "-o", "ppid=,comm="])
        if output.returncode:
            break
        fields = output.stdout.strip().split(None, 1)
        if len(fields) != PS_FIELD_COUNT:
            break
        parent, executable = fields
        parents.append({"pid": pid, "executable": executable})
        if executable == expected:
            return parents
        pid = int(parent)
        if pid <= 1:
            break
    fail(
        "Run this acceptance command inside the canonical ChatGPT GUI command runner; SSH/Terminal probes cannot validate its permission"
    )


def emit(value: str) -> None:
    """Write one live evidence line."""
    sys.stdout.write(value + "\n")
    sys.stdout.flush()


def resolve_endpoints(specifications: list[str]) -> list[tuple[str, str, int]]:
    """Pin validated numeric LAN destinations before issuing probes.

    Returns:
        Original labels, pinned numeric addresses and ports.

    """
    endpoints = []
    for endpoint in specifications:
        host, port = endpoint.rsplit(":", 1)
        if not host or not 1 <= int(port) <= MAX_PORT:
            fail("Invalid endpoint")
        addresses = socket.getaddrinfo(host, int(port), type=socket.SOCK_STREAM)
        for address in addresses:
            ip = ipaddress.ip_address(address[4][0])
            if not ip.is_private or ip.is_loopback or ip.is_unspecified:
                fail(
                    "Acceptance endpoints must resolve to LAN addresses; loopback cannot prove permission"
                )
            numeric = str(address[4][0])
            if address[0] == socket.AF_INET6 and address[4][-1]:
                numeric += "%" + str(address[4][-1])
            item = (host, numeric, int(port))
            if item not in endpoints:
                endpoints.append(item)
    if not endpoints:
        fail("No reachable LAN address was resolved")
    return endpoints


def acceptance(args: argparse.Namespace) -> int:
    """Test the selected LAN endpoints and stable GUI identity.

    Returns:
        Zero only when all probes and both identity checks pass.

    """
    parents = ancestry(args.app)
    endpoints = resolve_endpoints(args.endpoint)
    initial = run([args.lifecycle, "--mode", "check"])
    if initial.returncode:
        fail(initial.stderr)
    signature = run([
        "/usr/bin/codesign",
        "-d",
        "--verbose=4",
        str(args.app),
    ]).stderr
    emit(
        json.dumps({
            "origin": "canonical-gui-ancestor",
            "pid": os.getpid(),
            "parents": parents,
        })
    )
    start = time.monotonic()
    passed = True
    for number in range(5):
        threading.Event().wait(max(0, start + number * 30 - time.monotonic()))
        results = []
        for label, host, port in endpoints:
            tcp_error = None
            try:
                with socket.create_connection((host, port), timeout=5):
                    tcp = True
            except OSError as error:
                tcp = False
                tcp_error = {"errno": error.errno, "message": str(error)}
            framework = run([args.probe, host, str(port)])
            results.append({
                "endpoint": f"{label}:{port}",
                "address": host,
                "tcp": tcp,
                "tcpError": tcp_error,
                "networkFramework": framework.returncode == 0,
                "detail": framework.stdout.strip(),
            })
        passed = passed and all(
            item["tcp"] and item["networkFramework"] for item in results
        )
        emit(
            json.dumps({
                "round": number + 1,
                "elapsed": round(time.monotonic() - start, 2),
                "results": results,
            })
        )
    final = run([args.lifecycle, "--mode", "check"])
    same = initial.stdout == final.stdout and (
        signature
        == run(["/usr/bin/codesign", "-d", "--verbose=4", str(args.app)]).stderr
    )
    ancestry(args.app)
    passed = passed and final.returncode == 0 and same
    emit(
        json.dumps({
            "status": "passed" if passed else "failed",
            "identityStable": same,
            "authorization": "unknown",
        })
    )
    return 0 if passed else 1


def main() -> int:
    """Exercise explicit endpoints over two minutes without changing settings.

    Returns:
        The validated operation result.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--lifecycle", required=True)
    parser.add_argument("--probe", required=True)
    parser.add_argument(
        "--endpoint", action="append", required=True, help="HOST:PORT (IPv4 or DNS)"
    )
    args = parser.parse_args()
    try:
        result = acceptance(args)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        sys.stderr.write(str(error) + "\n")
        return 1
    return result


if __name__ == "__main__":
    sys.exit(main())
