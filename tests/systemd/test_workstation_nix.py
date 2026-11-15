"""Verify retained private-store builds without access to the host daemon."""

import argparse
import importlib.util
import json
import os
import signal
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

SOURCE = Path(__file__).parents[2] / "homes/desktop/local/scripts/workstation_nix.py"
SPEC = importlib.util.spec_from_file_location("workstation_nix", SOURCE)
assert SPEC is not None
assert SPEC.loader is not None
HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPER)
FAILURE = 23
ATTEMPTS = 2


def arguments(state: Path) -> argparse.Namespace:
    """Construct the public request without allowing caller Nix option overrides.

    Returns:
        A small build request using a task-owned store.

    """
    return argparse.Namespace(
        state=state,
        memory_gib=4,
        impure=False,
        file=None,
        installables=["github:example/project/immutable#check"],
    )


def nix_fixture(tmp_path: Path, code: int = 0) -> dict:
    """Provide a disposable builder that reports an immutable output.

    Returns:
        Runtime configuration pointing only at the test executable.

    """
    script = tmp_path / "nix"
    script.write_text(
        f"#!{sys.executable}\n"
        "import json,sys\nfrom pathlib import Path\n"
        f"Path({str(tmp_path / 'argv.json')!r}).write_text(json.dumps(sys.argv[1:]))\n"
        f"print(json.dumps([{{'drvPath':'/nix/store/proof.drv','outputs':{{'out':'/nix/store/proof'}}}}]))\n"
        f"sys.exit({code})\n"
    )
    script.chmod(0o755)
    return {"nix": str(script), "maxJobs": 1, "cores": 8}


def test_build_preserves_outputs_and_attempts(tmp_path: Path) -> None:
    """Separate attempts retain their own receipts, roots and immutable identities."""
    runtime = nix_fixture(tmp_path)
    args = arguments(tmp_path / "state & cache")
    assert HELPER.build(args, runtime) == 0
    assert HELPER.build(args, runtime) == 0
    receipts = list(args.state.glob("attempts/*/receipt.json"))
    assert len(receipts) == ATTEMPTS
    for receipt in receipts:
        value = json.loads(receipt.read_text())
        assert value["status"] == "succeeded"
        assert value["builds"][0]["drvPath"] == "/nix/store/proof.drv"
        assert value["physicalOutputs"] == [str(args.state / "store/nix/store/proof")]
    command = json.loads((tmp_path / "argv.json").read_text())
    assert command[command.index("--store") + 1].endswith("state%20%26%20cache/store")
    assert command[command.index("--cores") + 1] == "8"
    assert command[command.index("--max-jobs") + 1] == "1"
    assert command[command.index("--out-link") + 1].endswith("/result")
    assert not command[command.index("builders") + 1]
    assert command[command.index("sandbox") + 1] == "true"


def test_build_failure_is_not_retried(tmp_path: Path) -> None:
    """A failed payload stays failed with its original exit status."""
    assert (
        HELPER.build(arguments(tmp_path / "state"), nix_fixture(tmp_path, FAILURE))
        == FAILURE
    )
    receipts = list((tmp_path / "state").glob("attempts/*/receipt.json"))
    assert len(receipts) == 1
    receipt = json.loads(receipts[0].read_text())
    assert receipt["status"] == "failed"
    assert receipt["exitCode"] == FAILURE
    assert "physicalOutputs" not in receipt


def test_running_store_cannot_be_reused(tmp_path: Path) -> None:
    """The same state cannot be modified concurrently by a second caller."""
    state = tmp_path / "state"
    state.mkdir()
    with (state / "lock").open("w") as lock:
        HELPER.fcntl.flock(lock, HELPER.fcntl.LOCK_EX | HELPER.fcntl.LOCK_NB)
        with pytest.raises(BlockingIOError):
            HELPER.build(arguments(state), nix_fixture(tmp_path))


def test_abandoned_attempt_stays_interrupted(tmp_path: Path) -> None:
    """An abandoned receipt is reconciled without replay or an invented exit status."""
    state = tmp_path / "state"
    old = state / "attempts" / "old" / "receipt.json"
    old.parent.mkdir(parents=True)
    old.write_text(json.dumps({"status": "running", "command": ["original"]}))
    assert HELPER.build(arguments(state), nix_fixture(tmp_path)) == 0
    receipt = json.loads(old.read_text())
    assert receipt["status"] == "interrupted"
    assert receipt["termination"] == "unknown"
    assert receipt["exitCode"] is None
    assert receipt["command"] == ["original"]


def test_sigterm_is_recorded_before_exit(tmp_path: Path) -> None:
    """A real catchable cancellation unwinds into the retained interruption receipt."""

    def cancelled(*_args: object, **_kwargs: object) -> None:
        signal.raise_signal(signal.SIGTERM)

    previous = signal.getsignal(signal.SIGTERM)
    with (
        patch.object(HELPER.subprocess, "run", side_effect=cancelled),
        pytest.raises(SystemExit) as error,
    ):
        HELPER.build(arguments(tmp_path / "state"), nix_fixture(tmp_path))
    assert error.value.code == 128 + signal.SIGTERM
    assert signal.getsignal(signal.SIGTERM) == previous
    receipt = next((tmp_path / "state").glob("attempts/*/receipt.json"))
    assert json.loads(receipt.read_text())["status"] == "interrupted"


def test_allocation_refuses_ordinary_bulk_scope() -> None:
    """An outer daemon allocation must never be treated as a bounded builder."""
    with (
        patch.object(
            Path,
            "read_text",
            side_effect=[
                "0::/user.slice/background-workload.slice/owned.scope\n",
                "max\n",
            ],
        ),
        pytest.raises(ValueError, match="outermost"),
    ):
        HELPER.allocation(4)


def test_allocation_requires_hidden_daemon() -> None:
    """A numeric cap without the runner's filesystem isolation is insufficient."""
    with (
        patch.object(
            Path,
            "read_text",
            side_effect=[
                "0::/user.slice/background-workload.slice/owned.scope\n",
                str(4 * 1024**3),
                "0",
            ],
        ),
        patch.object(os, "statvfs") as stat,
        patch.object(Path, "exists", return_value=True),
    ):
        stat.return_value.f_flag = os.ST_RDONLY
        with pytest.raises(ValueError, match="outermost"):
            HELPER.allocation(4)


@pytest.mark.parametrize("requested", [None, "2", "5"])
def test_cli_uses_configured_allocation_range(
    tmp_path: Path, requested: str | None
) -> None:
    """The helper uses alternate host bounds and defaults rather than constants."""
    runtime = tmp_path / "runtime.json"
    runtime.write_text(
        json.dumps({
            "bounded": {
                "minimumMiB": 2048,
                "memoryMiB": 3072,
                "maximumMiB": 5120,
            }
        })
    )
    argv = [
        "workstation-nix",
        "--runtime-config",
        str(runtime),
        "--state",
        str(tmp_path),
        "fixture#check",
    ]
    if requested:
        argv += ["--memory-gib", requested]
    with (
        patch.object(HELPER.sys, "argv", argv),
        patch.object(HELPER, "allocation", return_value=True),
        patch.object(HELPER, "build", return_value=0) as build,
    ):
        assert HELPER.main() == 0
        assert build.call_args.args[0].memory_gib == (
            int(requested) if requested else 3
        )
    with (
        patch.object(HELPER.sys, "argv", [*argv, "--memory-gib", "1"]),
        pytest.raises(SystemExit),
    ):
        HELPER.main()


@pytest.mark.parametrize(("granted", "valid"), [(2, False), (4, True), (9, False)])
def test_elastic_outer_allocation_is_verified_from_kernel(
    granted: int, valid: bool
) -> None:
    """Only a contained, isolated grant within the requested range is reusable."""
    with (
        patch.object(
            Path,
            "read_text",
            side_effect=[
                "0::/user.slice/background-workload.slice/owned.scope\n",
                str(granted * 1024**3),
                "0",
            ],
        ),
        patch.object(os, "statvfs") as stat,
        patch.object(Path, "exists", return_value=False),
    ):
        stat.return_value.f_flag = os.ST_RDONLY
        if valid:
            assert HELPER.allocation(3, 8)
        else:
            with pytest.raises(ValueError, match="outermost"):
                HELPER.allocation(3, 8)
