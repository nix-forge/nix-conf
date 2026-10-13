"""Record an unchanged Deploy test binary and compare sandbox event delivery."""

import argparse
import hashlib
import json
import re
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Run reviewed source-built proof binaries without a shell.
from pathlib import Path
from typing import NoReturn

CASE = "tests::confirmation_watcher_observes_immediate_canary_removal"
WATCH_CASES = (
    CASE,
    "tests::wait_cancelled_when_cancel_file_created_while_waiting",
    "tests::wait_returns_when_canary_created_while_waiting",
)
_WINDOW = 10
_RUST_FAILURE = 101


def _reject(message: str) -> NoReturn:
    raise ValueError(message)


def record(binary: Path, probe: Path, output: Path) -> None:
    """Record diagnostic outcomes without turning timeouts into permission proof."""
    output.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Exact reviewed Rust test binary and fixed testcase.
        [str(binary), CASE, "--exact", "--nocapture"],
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    for index, case in enumerate(WATCH_CASES[1:], 1):
        other = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed reviewed watcher cases in the same binary.
            [str(binary), case, "--exact", "--nocapture"],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        (output / f"watch-{index}.log").write_text(other.stdout + other.stderr)
        (output / f"watch-{index}.json").write_text(
            json.dumps({"exit": other.returncode})
        )
    (output / "test.log").write_text(result.stdout + result.stderr)
    (output / "status.json").write_text(
        json.dumps({
            "exit": result.returncode,
            "binarySha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
            "probeSha256": hashlib.sha256(probe.read_bytes()).hexdigest(),
        })
    )
    capability = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Exact compiled FSEvents canary probe.
        [str(probe)], capture_output=True, text=True, timeout=15, check=True
    )
    (output / "fsevents.json").write_text(capability.stdout)


def _require_host_watchers(control: Path) -> None:
    """Require all other raw watcher cases to pass on the same host control."""
    for index, case in enumerate(WATCH_CASES[1:], 1):
        log = (control / f"watch-{index}.log").read_text()
        status = json.loads((control / f"watch-{index}.json").read_text())["exit"]
        if (
            status != 0
            or f"test {case} ... ok" not in log
            or "1 passed; 0 failed; 0 ignored" not in log
        ):
            _reject("All three unchanged host watcher cases must execute and pass")


def require_host_control(strict: Path, control: Path) -> None:
    """Require identical binaries, valid canaries and all real host watcher cases."""
    raw = json.loads((strict / "fsevents.json").read_text())
    host = json.loads((control / "fsevents.json").read_text())
    raw_status = json.loads((strict / "status.json").read_text())
    host_status = json.loads((control / "status.json").read_text())
    for key in ("binarySha256", "probeSha256"):
        if (
            not re.fullmatch(r"[0-9a-f]{64}", raw_status[key])
            or raw_status[key] != host_status[key]
        ):
            _reject("The paired runs did not execute identical binaries")
    for evidence in (raw, host):
        if (
            not all(
                evidence[key] is True
                for key in ("validDirectory", "createdStream", "removedCanary")
            )
            or evidence["windowSeconds"] != _WINDOW
        ):
            _reject("The real FSEvents canary preconditions did not pass")
    if host["startedStream"] is not True or host["removeCallbacks"] < 1:
        _reject("The capability-present control did not deliver removal")
    _require_host_watchers(control)
    passing = (control / "test.log").read_text()
    if host_status["exit"] != 0 or not (
        f"test {CASE} ... ok" in passing and "1 passed; 0 failed; 0 ignored" in passing
    ):
        _reject("The unchanged host testcase did not pass")


def compare(strict: Path, control: Path) -> None:
    """Keep audit admission tied to the precise sandbox event-loss differential."""
    require_host_control(strict, control)
    raw = json.loads((strict / "fsevents.json").read_text())
    raw_status = json.loads((strict / "status.json").read_text())
    failing = (strict / "test.log").read_text()
    if raw["removeCallbacks"] != 0:
        _reject("Strict sandbox delivered removal; investigate test timing")
    if raw_status["exit"] != _RUST_FAILURE or not (
        f"test {CASE} ... FAILED" in failing
        and "observe canary removal: TimesUp" in failing
        and "0 passed; 1 failed; 0 ignored" in failing
    ):
        _reject("Strict failure is not the exact observed removal timeout")
    print(  # ruff: ignore[print] - Report bounded diagnostic conclusion to CI.
        "Matched sandbox event non-delivery and successful host control; no permission-denial claim."
    )


def main() -> None:
    """Run one recording or compare separately captured identical-binary results."""
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="mode", required=True)
    recorder = subparsers.add_parser("record")
    recorder.add_argument("binary", type=Path)
    recorder.add_argument("probe", type=Path)
    recorder.add_argument("output", type=Path)
    comparator = subparsers.add_parser("compare")
    comparator.add_argument("strict", type=Path)
    comparator.add_argument("control", type=Path)
    args = parser.parse_args()
    if args.mode == "record":
        record(args.binary, args.probe, args.output)
    else:
        compare(args.strict, args.control)


if __name__ == "__main__":
    main()
