"""Require real normal and symlink-alias watcher cases on the native host."""

import argparse
import importlib.util
import json
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Execute reviewed source-built test artifacts without a shell.
from pathlib import Path
from typing import NoReturn

_CASES = (
    "tests::confirmation_watcher_observes_normal_directory_removal",
    "tests::confirmation_watcher_observes_symlink_directory_removal",
)
_RUST_FAILURE = 101


def _reject(message: str) -> NoReturn:
    raise ValueError(message)


def extra(binary: Path, output: Path) -> None:
    """Record both real-helper cases, preserving native failures as evidence."""
    output.mkdir(parents=True, exist_ok=True)
    for index, case in enumerate(_CASES):
        result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed reviewed tests from the supplied source-built artifact.
            [str(binary), case, "--exact", "--nocapture"],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        (output / f"directory-{index}.log").write_text(result.stdout + result.stderr)
        (output / f"directory-{index}.json").write_text(
            json.dumps({"exit": result.returncode})
        )


def require_case(folder: Path, index: int, *, passing: bool) -> None:
    """Check the executed exact case and its real native outcome."""
    log = (folder / f"directory-{index}.log").read_text()
    status = json.loads((folder / f"directory-{index}.json").read_text())["exit"]
    case = _CASES[index]
    if passing:
        if (
            status != 0
            or f"test {case} ... ok" not in log
            or "1 passed; 0 failed; 0 ignored" not in log
        ):
            _reject("Required real directory watcher did not execute and pass")
    elif not (
        status == _RUST_FAILURE
        and f"test {case} ... FAILED" in log
        and "observe real directory canary removal: TimesUp" in log
        and "0 passed; 1 failed; 0 ignored" in log
    ):
        _reject("The raw alias control did not show the precise path-matching failure")


def require_strict_original(folder: Path) -> None:
    """Keep both original creation watchers' precise unavailable results required."""
    cases = (
        "tests::wait_cancelled_when_cancel_file_created_while_waiting",
        "tests::wait_returns_when_canary_created_while_waiting",
    )
    symptoms = (
        "expected Cancelled, got Err(Waiting(TimesUp))",
        "observe canary creation: Waiting(TimesUp)",
    )
    for index, (case, symptom) in enumerate(zip(cases, symptoms, strict=True), 1):
        status = json.loads((folder / f"watch-{index}.json").read_text())["exit"]
        log = (folder / f"watch-{index}.log").read_text()
        if not (
            status == _RUST_FAILURE
            and f"test {case} ... FAILED" in log
            and symptom in log
            and "0 passed; 1 failed; 0 ignored" in log
        ):
            _reject("Strict original watcher evidence is missing or ambiguous")


def main() -> None:
    """Expose recording and fail-closed native source-repair comparisons."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="mode", required=True)
    recorder = commands.add_parser("extra")
    recorder.add_argument("binary", type=Path)
    recorder.add_argument("output", type=Path)
    host = commands.add_parser("host")
    host.add_argument("artifact", type=Path)
    host.add_argument("output", type=Path)
    baseline = commands.add_parser("raw-alias")
    baseline.add_argument("output", type=Path)
    proof = commands.add_parser("compare")
    proof.add_argument("artifact", type=Path)
    proof.add_argument("host", type=Path)
    args = parser.parse_args()
    if args.mode == "extra":
        extra(args.binary, args.output)
        return
    if args.mode == "raw-alias":
        require_case(args.output, 0, passing=True)
        require_case(args.output, 1, passing=False)
        return
    spec = importlib.util.spec_from_file_location(
        "native_pair", args.artifact / "compare.py"
    )
    if spec is None or spec.loader is None:
        _reject("The reviewed identical-binary pair classifier is missing")
    pair = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pair)
    if args.mode == "host":
        pair.record(
            args.artifact / "bin/activate-tests",
            args.artifact / "bin/fsevents-probe",
            args.output,
        )
        extra(args.artifact / "bin/activate-tests", args.output)
    else:
        pair.compare(args.artifact / "strict", args.host)
        require_strict_original(args.artifact / "strict")
        require_case(args.artifact / "strict", 0, passing=False)
        require_case(args.artifact / "strict", 1, passing=False)
        require_case(args.host, 0, passing=True)
        require_case(args.host, 1, passing=True)


if __name__ == "__main__":
    main()
