"""Small native queue probes; run against a new/drained deployment only."""
# Explicit argv drives only this probe's finite, owner-labelled fixtures.
# ruff: file-ignore[suspicious-subprocess-import, subprocess-without-shell-equals-true, print, magic-value-comparison]

import argparse
import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path


def main() -> None:
    """Check submission, payload results, limits, identity and finite timeout.

    Raises:
        RuntimeError: A native queue contract failed.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("client", type=Path)
    parser.add_argument("--profile", default="bounded")
    parser.add_argument("--memory-mib", default="256")
    parser.add_argument("--state", type=Path, required=True)
    args = parser.parse_args()
    args.state.mkdir(mode=0o700, parents=True, exist_ok=True)
    nonce = uuid.uuid4().hex
    identifiers = []

    def client(*arguments: str, expected: int = 0) -> str:
        result = subprocess.run(
            [str(args.client), *arguments],
            capture_output=True,
            text=True,
            check=False,
            timeout=60,
        )
        if result.returncode != expected:
            message = f"Unexpected client exit {result.returncode}: {result.stdout} {result.stderr}"
            raise RuntimeError(message)
        return result.stdout.strip()

    def submit(
        key: str, code: str, *, seconds: int = 30, extra: tuple[str, ...] = ()
    ) -> str:
        identifier = client(
            "submit",
            "--owner",
            "scheduler-native-validation",
            "--key",
            nonce + key,
            "--source",
            "immutable-native-fixture-v1",
            "--cwd",
            str(args.state),
            "--profile",
            args.profile,
            "--memory-mib",
            args.memory_mib,
            "--timeout",
            str(seconds),
            "--",
            sys.executable,
            "-c",
            code,
            *extra,
        )
        if identifier not in identifiers:
            identifiers.append(identifier)
        return identifier

    code = """import json, os, pathlib, sys
result = {"argv":sys.argv[1:], "cwd":os.getcwd(), "secret":os.environ.get("SCHEDULER_TEST_SECRET"), "nix":os.environ.get("NIX_CONFIG")}
if pathlib.Path("/proc/self/cgroup").exists():
    group = pathlib.Path("/proc/self/cgroup").read_text().split("::",1)[1].strip()
    root = pathlib.Path("/sys/fs/cgroup") / group.lstrip("/")
    result["memoryMax"] = (root / "memory.max").read_text().strip()
    result["swapMax"] = (root / "memory.swap.max").read_text().strip()
    result["memoryPeak"] = (root / "memory.peak").read_text().strip()
pathlib.Path("payload.json").write_text(json.dumps(result))
print(json.dumps(result))
"""
    os.environ["SCHEDULER_TEST_SECRET"] = "synthetic-not-a-credential"  # ruff: ignore[hardcoded-password-string] - synthetic environment exclusion fixture
    first = submit("argv", code, extra=("space and $literal", "a;exit 99"))
    duplicate = submit("argv", code, extra=("space and $literal", "a;exit 99"))
    if duplicate != first:
        message = "Repeated request created a duplicate job"
        raise RuntimeError(message)
    client("wait", "--timeout", "40", first)
    payload = json.loads((args.state / "payload.json").read_text(encoding="utf-8"))
    if (
        payload["argv"] != ["space and $literal", "a;exit 99"]
        or payload["secret"] is not None
        or payload["cwd"] != str(args.state)
    ):
        message = "Argument, environment or working directory contract failed"
        raise RuntimeError(message)
    if (
        "memoryMax" in payload
        and int(payload["memoryMax"]) != int(args.memory_mib) * 1024**2
    ):
        message = "Actual cgroup memory cap differs from the requested profile"
        raise RuntimeError(message)
    failed = submit("payload75", "import sys; sys.exit(75)")
    client("wait", "--timeout", "40", failed, expected=1)
    failed_record = json.loads(client("status", failed))["jobs"][0]
    if (
        failed_record["receipt"]["phase"] != "failed"
        or failed_record["receipt"]["exitCode"] != 75
    ):
        message = "Payload exit75 was misclassified as admission or retried"
        raise RuntimeError(message)
    timed = submit("timeout", "import time; time.sleep(30)", seconds=2)
    client("wait", "--timeout", "15", timed, expected=1)
    timeout_record = json.loads(client("status", timed))["jobs"][0]
    if (
        timeout_record["receipt"]["phase"] != "timeout"
        or not timeout_record["receipt"]["drained"]
    ):
        message = "Finite execution deadline did not drain its owned workload"
        raise RuntimeError(message)
    result = {
        "time": time.time(),
        "jobs": identifiers,
        "payload": payload,
        "failure": failed_record,
        "timeout": timeout_record,
        "passed": True,
    }
    (args.state / "verification.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8"
    )
    print(
        json.dumps({
            "passed": True,
            "jobs": identifiers,
            "receipt": str(args.state / "verification.json"),
        })
    )


if __name__ == "__main__":
    main()
