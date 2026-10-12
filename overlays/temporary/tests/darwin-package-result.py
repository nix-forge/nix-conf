"""Require specific native Darwin failures and real preserved Rust tests."""

import argparse
import json
import re
from pathlib import Path
from typing import NoReturn

_CARGO_FAILURE = 101
_SENTRY_NAMES = {
    "sentry",
    "main - nix-functional-tests:sentry",
    "nix-functional-tests:main / sentry",
    "nix-functional-tests / sentry",
}
_MACH_OPERATION = re.compile(
    r"(?:bootstrap_(?:check_in|register|look_up)|mach_port_[a-z_]+)[^\n]*(?:Permission denied|Operation not permitted|not privileged|BOOTSTRAP_NOT_PRIVILEGED|\(1100\))",
    re.IGNORECASE,
)
_DEPLOY_CASE = "tests::confirmation_watcher_observes_immediate_canary_removal"
_HOME_CASE = "command::tests::test_elevated_darwin_home_is_absolute"


def _reject(message: str) -> NoReturn:
    raise ValueError(message)


def sentry(records: list[dict[str, object]], status: int) -> None:
    """Accept only the real Sentry no-dump failure with explicit Mach denial."""
    if status != 1 or len(records) != 1:
        _reject("The baseline must execute only one failing native Sentry case")
    case = records[0]
    if (
        case.get("name") not in _SENTRY_NAMES
        or case.get("result") != "FAIL"
        or case.get("returncode") != 1
    ):
        _reject("Expected exact Sentry FAIL/exit1, never SKIP or another case")
    diagnostic = str(case.get("stdout", "")) + "\n" + str(case.get("stderr", ""))
    if "No crash dump found in " not in diagnostic or not _MACH_OPERATION.search(
        diagnostic
    ):
        _reject("Missing precise no-crashdump and explicit Mach permission denial")


def home(log: str) -> None:
    """Require the actual added absolute-HOME test to execute and pass."""
    if f"test {_HOME_CASE} ... ok" not in log or "1 passed; 0 failed;" not in log:
        _reject("The native Darwin absolute-root-HOME regression did not pass")


def sentinel(log: str, mode: str) -> None:
    """Require preserved non-watcher sentinel cases to execute and pass."""
    cases = {
        "sentinel-existing": "tests::wait_cancelled_when_cancel_file_already_exists",
        "sentinel-removal": "tests::remove_activation_cancel_clears_the_sentinel",
    }
    if f"test {cases[mode]} ... ok" not in log or "1 passed; 0 failed;" not in log:
        _reject("A preserved non-watcher sentinel case did not pass")


def deploy(log: str, status: int) -> None:
    """Accept only the original native watcher case with explicit service denial."""
    if status != _CARGO_FAILURE or f"test {_DEPLOY_CASE} ... FAILED" not in log:
        _reject("The raw native confirmation watcher case did not fail exactly")
    if "create confirmation watcher" not in log:
        _reject("The original case did not fail at watcher creation")
    if not re.search(
        r"(?:FSEvent|fsevent|watcher)[^\n]*(?:Permission denied|Operation not permitted|not privileged)",
        log,
    ):
        _reject("No explicit native FSEvents/watch service permission denial")


def main() -> None:
    """Check captured evidence from one isolated native proof."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "mode",
        choices=["sentry", "home", "deploy", "sentinel-existing", "sentinel-removal"],
    )
    parser.add_argument("result", type=Path)
    parser.add_argument("--status", type=int, default=0)
    args = parser.parse_args()
    log = args.result.read_text()
    if args.mode == "sentry":
        sentry(
            [json.loads(line) for line in log.splitlines() if line.strip()], args.status
        )
    elif args.mode == "home":
        home(log)
    elif args.mode == "deploy":
        deploy(log, args.status)
    else:
        sentinel(log, args.mode)
    print(f"Verified native Darwin package evidence: {args.mode}")  # ruff: ignore[print] - Report native result classification to CI.


if __name__ == "__main__":
    main()
