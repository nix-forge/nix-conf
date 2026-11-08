"""Request identity, restart reconciliation and honest terminal semantics."""
# These unit fixtures exercise internal transactional seams and synthetic secrets.
# ruff: file-ignore[private-member-access, hardcoded-password-string, hardcoded-temp-file, magic-value-comparison]

import asyncio
import contextlib
import importlib.util
import json
import os
import shutil
import signal
import sys
import time
from argparse import Namespace
from pathlib import Path
from types import SimpleNamespace
from typing import TYPE_CHECKING, TypedDict

import pytest

if TYPE_CHECKING:
    from _pytest.monkeypatch import MonkeyPatch

SOURCE = (
    Path(__file__).parents[2]
    / "modules/home/services/workstation-jobs-assets/workstation_job.py"
)
SPEC = importlib.util.spec_from_file_location("workstation_job", SOURCE)
assert SPEC
assert SPEC.loader
jobs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(jobs)

pytestmark = pytest.mark.usefixtures("external_submitter_context")


@pytest.fixture
def external_submitter_context(monkeypatch: MonkeyPatch) -> None:
    """Submission fixtures model an external client, even inside a queued test."""
    monkeypatch.delenv("WORKSTATION_JOB_ID", raising=False)


def test_environment_does_not_persist_agent_secrets(monkeypatch: MonkeyPatch) -> None:
    """Environment does not persist agent secrets."""
    monkeypatch.setenv("HOME", "/fixture")
    monkeypatch.setenv("PRIVATE_API_TOKEN", "do-not-persist")
    assert jobs._filtered_environment()["HOME"] == "/fixture"
    assert "PRIVATE_API_TOKEN" not in jobs._filtered_environment()
    assert (
        jobs._filtered_environment(["PRIVATE_API_TOKEN"])["PRIVATE_API_TOKEN"]
        == "do-not-persist"
    )


def test_native_terminal_variants() -> None:
    """Native terminal variants."""
    assert jobs._terminal({"status": {"Running": {}}}) is None
    assert (
        jobs._terminal({"status": {"Done": {"result": "Success"}}})["result"]
        == "Success"
    )
    assert (
        jobs._terminal({"status": {"Done": {"result": {"Failed": 75}}}})["result"]
        != "Success"
    )
    assert (
        jobs._terminal({"status": {"Done": {"result": "Killed"}}})["result"]
        != "Success"
    )


def test_inspect_keeps_active_and_unresolved_jobs_before_recent_history(
    tmp_path: Path, monkeypatch: MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    """Random IDs cannot hide active work, and history follows creation time."""
    tasks = {}
    for index in range(105):
        identifier = f"{index:032x}"
        directory = tmp_path / "jobs" / identifier
        directory.mkdir(parents=True)
        jobs._save(
            directory / "recipe.json",
            {
                "id": identifier,
                "owner": "fixture",
                "profile": "bounded",
                "sourceReference": "fixture",
                "created": 200 - index,
            },
        )
        jobs._save(directory / "submission.json", {"taskId": str(index)})
        status = {"Running": {}} if index == 0 else {"Done": {"result": "Success"}}
        tasks[str(index)] = {"label": "wj:" + identifier, "status": status}
        if index != 1:
            jobs._save(
                directory / "result.json",
                {
                    "drained": index != 0,
                    "exitCode": None if index == 0 else 0,
                },
            )
    tasks["104"]["status"] = {"Queued": {}}
    jobs._save(
        tmp_path / "jobs" / f"{104:032x}" / "result.json",
        {
            "phase": "cancelled-before-start",
            "drained": True,
            "exitCode": 130,
        },
    )
    monkeypatch.setattr(jobs, "_snapshot", lambda _: {"groups": {}, "tasks": tasks})
    jobs._inspect({"stateDirectory": str(tmp_path)})
    reported = json.loads(capsys.readouterr().out)["jobs"]
    identifiers = [job["id"] for job in reported]
    assert identifiers[:3] == [f"{0:032x}", f"{1:032x}", f"{104:032x}"]
    assert identifiers[3:] == [f"{index:032x}" for index in range(2, 102)]


@pytest.mark.parametrize(
    ("requested", "memory", "timeout", "daemon", "expected"),
    [
        ("auto", None, None, False, "bounded"),
        ("auto", 2048, 120, False, "feedback"),
        ("auto", 2048, 121, False, "bounded"),
        ("auto", 4096, 120, False, "bounded"),
        ("auto", 1024, 120, False, "bounded"),
        ("auto", None, None, True, "daemon"),
        ("bounded", 2048, 120, False, "bounded"),
        (None, 2048, 120, False, "bounded"),
        (None, None, None, True, "daemon"),
    ],
)
def test_resource_declared_routing(
    requested: str | None,
    memory: int | None,
    timeout: int | None,
    daemon: bool,
    expected: str,
) -> None:
    """Only an explicit daemon requirement can leave the confined profiles."""
    cfg = {
        "profiles": {
            "bounded": {"minimumMiB": 1024, "maximumMiB": 6144, "maximumSeconds": 1800},
            "feedback": {"minimumMiB": 2048, "maximumMiB": 2048, "maximumSeconds": 120},
            "daemon": {"minimumMiB": 8192, "maximumMiB": 8192, "maximumSeconds": 86400},
        }
    }
    args = Namespace(
        profile=requested, memory_mib=memory, timeout=timeout, requires_daemon=daemon
    )
    assert jobs._select_profile(cfg, args) == expected


def test_auto_routing_never_promotes_oversized_work_to_daemon() -> None:
    """A large request remains bounded so its normal range check refuses it."""
    args = Namespace(
        profile="auto", memory_mib=8192, timeout=1200, requires_daemon=False
    )
    assert (
        jobs._select_profile({"profiles": {"bounded": {}, "daemon": {}}}, args)
        == "bounded"
    )
    args.requires_daemon = True
    args.profile = "bounded"
    with pytest.raises(ValueError, match="requires-daemon"):
        jobs._select_profile({"profiles": {"bounded": {}, "daemon": {}}}, args)


@pytest.mark.parametrize(
    ("flags", "expected"),
    [
        ([], "bounded"),
        (["--requires-daemon"], "daemon"),
        (["--profile", "bounded", "--requires-daemon"], None),
    ],
)
def test_cli_distinguishes_omitted_and_explicit_profile(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
    flags: list[str],
    expected: str | None,
) -> None:
    """The daemon flag works alone while explicit confined profiles fail closed."""
    config = tmp_path / "config.json"
    jobs._save(
        config,
        {"stateDirectory": str(tmp_path), "profiles": {"bounded": {}, "daemon": {}}},
    )
    selected = []
    monkeypatch.setattr(
        jobs,
        "_submit",
        lambda cfg, _path, args: selected.append(jobs._select_profile(cfg, args)),
    )
    monkeypatch.setattr(
        sys,
        "argv",
        [
            str(SOURCE),
            "--config",
            str(config),
            "submit",
            "--owner",
            "fixture",
            "--key",
            "once",
            "--source",
            "frozen",
            *flags,
            "--",
            "true",
        ],
    )
    if expected is None:
        with pytest.raises(ValueError, match="requires-daemon"):
            jobs.main()
    else:
        assert jobs.main() == 0
        assert selected == [expected]


def test_atomic_private_record(tmp_path: Path) -> None:
    """Atomic private record."""
    Path(tmp_path).chmod(0o700)
    previous = os.umask(0o077)
    try:
        target = tmp_path / "receipt.json"
        jobs._save(target, {"exitCode": 75})
        assert json.loads(target.read_text()) == {"exitCode": 75}
        assert target.stat().st_mode & 0o777 == 0o600
        assert not target.with_suffix(".tmp").exists()
    finally:
        os.umask(previous)


@pytest.mark.parametrize("identifier", ["../owner", "/tmp/other", "1", "x" * 32])
def test_ids_cannot_escape_owned_directory(tmp_path: Path, identifier: str) -> None:
    """Ids cannot escape owned directory."""
    with pytest.raises(ValueError, match="stable workstation-job ID"):
        jobs._job_path(tmp_path, identifier)


def test_recovery_preserves_live_interrupted_worker(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Recovery preserves live interrupted worker."""
    directory = tmp_path / "jobs" / ("a" * 32)
    directory.mkdir(parents=True)
    jobs._save(
        directory / "result.json",
        {"wrapperPid": 77, "wrapperIdentity": "fixture-start", "drained": False},
    )
    monkeypatch.setattr(jobs, "_process_identity", lambda *_: "fixture-start")
    with pytest.raises(ValueError, match="still present"):
        jobs._resume({"stateDirectory": str(tmp_path), "profiles": {"bounded": {}}})


def test_resume_only_starts_groups_not_interrupted_jobs(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Resume only starts groups not interrupted jobs."""
    commands = []
    monkeypatch.setattr(jobs, "_native", lambda _, *args: commands.append(args))
    jobs._resume({
        "stateDirectory": str(tmp_path),
        "profiles": {"bounded": {}, "daemon": {}},
    })
    assert commands == [("start", "--group", "bounded"), ("start", "--group", "daemon")]


def test_init_preserves_recovery_pause(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Init preserves recovery pause."""
    commands = []
    monkeypatch.setattr(
        jobs, "_snapshot", lambda _: {"groups": {"bounded": {"status": "Paused"}}}
    )
    monkeypatch.setattr(jobs, "_native", lambda _, *args: commands.append(args))
    jobs._initialise({"stateDirectory": str(tmp_path), "profiles": {"bounded": {}}})
    assert not any(command[0] == "start" for command in commands)
    assert ("pause", "--group", "default", "--wait") in commands


def test_stale_numeric_id_fails_closed() -> None:
    """Recycled native IDs cannot address another owner's job."""
    with pytest.raises(ValueError, match="no longer belongs"):
        jobs._validate_native_identity({"label": "wj:other-owner"}, "a" * 32)
    jobs._validate_native_identity({"label": "wj:" + "a" * 32}, "a" * 32)


def test_activation_refuses_busy_queue(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """An update never pauses or replaces an active worker."""
    commands = []
    monkeypatch.setattr(
        jobs, "_snapshot", lambda _: {"tasks": {"7": {"status": {"Running": {}}}}}
    )
    monkeypatch.setattr(jobs, "_native", lambda _, *args: commands.append(args))
    with pytest.raises(ValueError, match="unfinished jobs"):
        jobs._activation_check({"stateDirectory": str(tmp_path)})
    assert not commands
    assert not (tmp_path / "maintenance.json").exists()


def test_activation_restores_only_previously_running_groups(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """A reviewed idle update preserves a manually paused group."""
    commands = []
    groups = {"bounded": {"status": "Running"}, "manual": {"status": "Paused"}}
    monkeypatch.setattr(jobs, "_snapshot", lambda _: {"tasks": {}, "groups": groups})
    monkeypatch.setattr(jobs, "_native", lambda _, *args: commands.append(args))
    cfg = {"stateDirectory": str(tmp_path)}
    jobs._activation_check(cfg)
    assert (tmp_path / "maintenance.json").exists()
    jobs._activation_finish(cfg)
    assert commands == [
        ("pause", "--group", "bounded", "--wait"),
        ("pause", "--group", "manual", "--wait"),
        ("start", "--group", "bounded"),
    ]
    assert not (tmp_path / "maintenance.json").exists()


def test_activation_accepts_only_verified_unclaimed_cancellation(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """A preserved cancellation permits upgrades; ambiguous stashes do not."""
    identifier = "a" * 32
    directory = jobs._job_path(tmp_path, identifier)
    directory.mkdir(parents=True)
    task = {"label": "wj:" + identifier, "status": {"Stashed": {"enqueue_at": None}}}
    monkeypatch.setattr(
        jobs, "_snapshot", lambda _: {"tasks": {"7": task}, "groups": {}}
    )
    cfg = {"stateDirectory": str(tmp_path)}
    with pytest.raises(ValueError, match="unfinished jobs"):
        jobs._activation_check(cfg)
    jobs._save(
        directory / "result.json",
        {
            "id": identifier,
            "phase": "cancelled-before-start",
            "exitCode": 130,
            "drained": True,
        },
    )
    jobs._activation_check(cfg)
    (tmp_path / "maintenance.json").unlink()
    jobs._claim_execution(directory)
    with pytest.raises(ValueError, match="unfinished jobs"):
        jobs._activation_check(cfg)


@pytest.mark.parametrize("elastic", [False, True])
def test_duplicate_request_and_changed_specification(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    elastic: bool,
) -> None:
    """A repeated request reuses one native job; a changed request fails closed."""
    cfg = {
        "stateDirectory": str(tmp_path),
        "pueue": "pueue-fixture",
        "pueueConfig": "fixture.yml",
        "profiles": {
            "bounded": {
                "backend": "systemd",
                "memoryMiB": 256,
                "minimumMiB": 64,
                "maximumMiB": 512,
                "maximumSeconds": 30,
            }
        },
    }
    args = Namespace(
        command=["echo", "fixture"],
        profile="bounded",
        memory_mib=None if elastic else 256,
        memory_min_mib=64 if elastic else None,
        memory_max_mib=256 if elastic else None,
        timeout=10,
        owner="fixture-owner",
        key="once",
        cwd=str(tmp_path),
        source="frozen-fixture",
        env=[],
    )
    calls = []
    monkeypatch.setattr(jobs, "_root_store", lambda *_args: None)
    monkeypatch.setattr(jobs, "_snapshot", lambda _: {"tasks": {}})
    monkeypatch.setattr(
        jobs.subprocess,
        "run",
        lambda *args, **_kwargs: calls.append(args) or SimpleNamespace(stdout="42\n"),
    )
    jobs._submit(cfg, "fixture-config", args)
    first = capsys.readouterr().out.strip()
    recipe = jobs._read(tmp_path / "jobs" / first / "recipe.json")
    assert ("memoryRange" in recipe) == elastic
    if elastic:
        assert recipe["memoryRange"] == {"minimumMiB": 64, "maximumMiB": 256}
    jobs._submit(cfg, "fixture-config", args)
    assert capsys.readouterr().out.strip() == first
    assert len(calls) == 1
    args.command = ["echo", "changed"]
    with pytest.raises(ValueError, match="different immutable job"):
        jobs._submit(cfg, "fixture-config", args)
    assert len(calls) == 1


def test_lost_acknowledgment_reconciles_without_resubmit(
    tmp_path: Path, monkeypatch: MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    """A server-created task is recovered by its stable label after transport loss."""
    cfg = {
        "stateDirectory": str(tmp_path),
        "pueue": "pueue-fixture",
        "pueueConfig": "fixture.yml",
        "profiles": {
            "bounded": {
                "backend": "systemd",
                "memoryMiB": 256,
                "minimumMiB": 64,
                "maximumMiB": 512,
                "maximumSeconds": 30,
            }
        },
    }
    args = Namespace(
        command=["echo"],
        profile="bounded",
        memory_mib=256,
        timeout=10,
        owner="fixture",
        key="lost",
        cwd=str(tmp_path),
        source="frozen",
        env=[],
    )
    monkeypatch.setattr(jobs, "_root_store", lambda *_args: None)
    monkeypatch.setattr(jobs, "_snapshot", lambda _: {"tasks": {}})

    def disconnect(*_args: object, **_kwargs: object) -> None:
        raise jobs.subprocess.CalledProcessError(1, "fixture-disconnect")

    monkeypatch.setattr(jobs.subprocess, "run", disconnect)
    with pytest.raises(jobs.subprocess.CalledProcessError):
        jobs._submit(cfg, "fixture-config", args)
    identifier = next((tmp_path / "jobs").iterdir()).name
    monkeypatch.setattr(
        jobs, "_snapshot", lambda _: {"tasks": {"19": {"label": "wj:" + identifier}}}
    )
    jobs._submit(cfg, "fixture-config", args)
    assert capsys.readouterr().out.strip() == identifier
    assert (
        jobs._read(tmp_path / "jobs" / identifier / "submission.json")["taskId"] == "19"
    )


def test_inherited_pipe_cannot_outlive_deadline(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """A detached pipe holder yields a bounded, honestly undrained failure."""
    ps = shutil.which("ps")
    if ps is None:
        pytest.skip("native ps is required for this process supervision fixture")
    monkeypatch.setattr(jobs, "_available", lambda: 1024**4)
    monkeypatch.setattr(jobs, "_group_usage", lambda _: 0)
    child_code = "import time; time.sleep(20)"
    code = f"import subprocess,sys,pathlib; child=subprocess.Popen([sys.executable,'-c',{child_code!r}],start_new_session=True); pathlib.Path('child.pid').write_text(str(child.pid))"
    recipe = {
        "id": "fixture",
        "profile": "bounded",
        "memoryMiB": 256,
        "timeout": 1,
        "sourceReference": "frozen",
        "environment": {},
        "command": [sys.executable, "-c", code],
        "cwd": str(tmp_path),
        "config": {
            "profiles": {"bounded": {"backend": "darwin"}},
            "reserveMiB": 1,
            "compilerCores": 2,
            "path": os.environ.get("PATH", ""),
            "ps": ps,
        },
    }
    started = time.monotonic()
    try:
        assert asyncio.run(jobs._supervise(recipe, tmp_path)) == 124
        assert time.monotonic() - started < 10
        receipt = jobs._read(tmp_path / "result.json")
        assert receipt["phase"] == "timeout"
        assert not receipt["drained"]
    finally:
        marker = tmp_path / "child.pid"
        if marker.exists():
            os.kill(int(marker.read_text(encoding="utf-8")), signal.SIGTERM)


@pytest.mark.parametrize(
    ("samples", "expected"),
    [
        ([8, "timeout", 0], ("succeeded", 8, 0, 1, 0)),
        ([16, "timeout", "timeout"], ("supervision-error", 16, 16, 2, 2)),
        (["timeout", 4, "timeout", 0], ("succeeded", 4, 0, 2, 0)),
        (["timeout", 257], ("memory-limit-observed", 257, 257, 1, 0)),
        (["invalid"], ("supervision-error", 0, None, 0, 0)),
    ],
    ids=["recovery", "persistent", "separated", "memory-limit", "malformed"],
)
def test_native_sampling_preserves_observations_and_fails_closed(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
    samples: list[int | str],
    expected: tuple[str, int, int | None, int, int],
) -> None:
    """Real child scopes cannot finish on a missed or invalid RSS sample."""
    phase, peak, last, missed, consecutive = expected
    measurements = iter(samples)
    calls = []

    def measure(pid: int) -> int:
        calls.append(pid)
        sample = next(measurements, 0)
        if sample == "timeout":
            raise jobs.subprocess.TimeoutExpired(["/bin/ps"], 1)
        if sample == "invalid":
            message = "invalid fixture RSS"
            raise ValueError(message)
        assert isinstance(sample, int)
        return sample * jobs.MIB

    monkeypatch.setattr(jobs, "_group_usage", measure)
    receipt = _native_sampling_child(
        tmp_path, monkeypatch, sleep=20 if phase == "memory-limit-observed" else 0
    )
    assert receipt["phase"] == phase
    assert receipt["exitCode"] == (0 if phase == "succeeded" else 1)
    assert len(calls) == len(samples)
    assert receipt["observedGroupPeakBytes"] == peak * jobs.MIB
    assert receipt["lastObservedGroupBytes"] == (
        None if last is None else last * jobs.MIB
    )
    assert receipt["memorySamplingTimeouts"] == missed
    assert receipt["memorySamplingConsecutiveTimeouts"] == consecutive
    if phase == "supervision-error":
        assert receipt["supervisionErrorType"] == (
            "ValueError" if samples == ["invalid"] else "TimeoutExpired"
        )


@pytest.mark.parametrize("cancel", [False, True])
def test_missed_native_sample_preserves_deadline_and_cancellation(
    tmp_path: Path, monkeypatch: MonkeyPatch, *, cancel: bool
) -> None:
    """A missed measurement does not defer a real deadline or cancellation."""
    calls = []

    def measure(pid: int) -> int:
        calls.append(pid)
        if cancel:
            asyncio.get_running_loop().call_soon(os.kill, os.getpid(), signal.SIGTERM)
        raise jobs.subprocess.TimeoutExpired(["/bin/ps"], 1)

    monkeypatch.setattr(jobs, "_group_usage", measure)
    started = time.monotonic()
    receipt = _native_sampling_child(tmp_path, monkeypatch, timeout=1, sleep=20)
    assert time.monotonic() - started < 10
    assert receipt["phase"] == ("cancelled" if cancel else "timeout")
    assert receipt["exitCode"] == (1 if cancel else 124)
    assert len(calls) == 1
    assert receipt["memorySamplingTimeouts"] == 1
    assert receipt["memorySamplingConsecutiveTimeouts"] == 1
    assert receipt["lastObservedGroupBytes"] is None
    assert receipt["observedGroupPeakBytes"] == 0


class SamplingReceipt(TypedDict):
    """Native supervision observations asserted by the real-process fixtures."""

    phase: str
    exitCode: int
    observedGroupPeakBytes: int
    lastObservedGroupBytes: int | None
    memorySamplingTimeouts: int
    memorySamplingConsecutiveTimeouts: int
    supervisionErrorType: str
    nativeCleanupErrorTypes: list[str]
    drained: bool
    pid: int


def _native_sampling_child(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
    *,
    timeout: int = 15,
    sleep: int = 0,
    expected_drained: bool = True,
) -> SamplingReceipt:
    """Run real owned children while injecting only native accounting outcomes.

    Returns:
        The durable receipt after asserting child exit and process-group absence.

    """
    ps = shutil.which("ps")
    if ps is None:
        pytest.skip("native ps is required for this process supervision fixture")
    monkeypatch.setattr(jobs, "_available", lambda: 1024**4)
    monkeypatch.setattr(jobs, "_host_memory_pressure", lambda: "fixture-normal")
    recipe = {
        "id": "sampling-fixture",
        "profile": "bounded",
        "memoryMiB": 256,
        "timeout": timeout,
        "sourceReference": "frozen-sampling-fixture",
        "environment": {},
        "command": [sys.executable, "-c", f"import time; time.sleep({sleep})"],
        "cwd": str(tmp_path),
        "config": {
            "profiles": {"bounded": {"backend": "darwin"}},
            "reserveMiB": 1,
            "compilerCores": 8,
            "path": os.environ.get("PATH", ""),
            "ps": ps,
        },
    }
    signals = (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)
    previous = {sig: signal.getsignal(sig) for sig in signals}
    try:
        code = asyncio.run(jobs._supervise(recipe, tmp_path))
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)
    receipt = jobs._read(tmp_path / "result.json")
    assert code == receipt["exitCode"]
    assert receipt["drained"] is expected_drained
    with pytest.raises(ProcessLookupError):
        os.killpg(receipt["pid"], 0)
    return receipt


def test_execution_claim_is_never_replayed(tmp_path: Path) -> None:
    """A stale native journal cannot launch the same payload twice."""
    jobs._claim_execution(tmp_path)
    first = (tmp_path / "execution.claim").read_bytes()
    with pytest.raises(ValueError, match="already claimed"):
        jobs._claim_execution(tmp_path)
    assert (tmp_path / "execution.claim").read_bytes() == first


def test_recovery_resumes_only_unclaimed_queued_work(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Never-started queued work recovers while manual pauses remain paused."""
    identifier = "a" * 32
    directory = tmp_path / "jobs" / identifier
    directory.mkdir(parents=True)
    jobs._save(directory / "recipe.json", {"id": identifier})
    state = {
        "groups": {"bounded": {"status": "Paused"}},
        "tasks": {
            "1": {
                "group": "bounded",
                "label": "wj:" + identifier,
                "status": {"Queued": {}},
            }
        },
    }
    commands = []
    monkeypatch.setattr(jobs, "_snapshot", lambda _: state)
    monkeypatch.setattr(jobs, "_native", lambda _, *args: commands.append(args))
    cfg = {"stateDirectory": str(tmp_path), "profiles": {"bounded": {}}}
    previous = {"groups": {"bounded": {"status": "Running"}}, "tasks": {}}
    jobs._recover_queued(cfg, previous)
    assert commands == [("start", "--group", "bounded")]
    commands.clear()
    previous["groups"]["bounded"]["status"] = "Paused"
    jobs._recover_queued(cfg, previous)
    assert not commands
    previous["groups"]["bounded"]["status"] = "Running"
    jobs._claim_execution(directory)
    jobs._recover_queued(cfg, previous)
    assert commands == [("pause", "--group", "bounded", "--wait")]
    assert jobs._read(tmp_path / "queue-health.json")["needsReconciliation"]


def test_failed_activation_retry_preserves_original_pause_intent(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """A second activation retains the first maintenance transaction's intent."""
    groups = {"bounded": {"status": "Running"}}
    commands = []
    monkeypatch.setattr(jobs, "_snapshot", lambda _: {"tasks": {}, "groups": groups})
    monkeypatch.setattr(jobs, "_native", lambda _, *args: commands.append(args))
    cfg = {"stateDirectory": str(tmp_path)}
    jobs._activation_check(cfg)
    original = jobs._read(tmp_path / "maintenance.json")
    groups["bounded"]["status"] = "Paused"
    jobs._activation_check(cfg)
    assert jobs._read(tmp_path / "maintenance.json") == original
    jobs._activation_finish(cfg)
    assert commands[-1] == ("start", "--group", "bounded")


def test_wait_revalidates_terminal_identity(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """A reset during a long wait cannot turn another task into a passing check."""
    identifier = "b" * 32
    directory = tmp_path / "jobs" / identifier
    directory.mkdir(parents=True)
    jobs._save(directory / "submission.json", {"taskId": "7"})
    config = tmp_path / "config.json"
    jobs._save(config, {"stateDirectory": str(tmp_path)})
    states = iter([
        {"tasks": {"7": {"label": "wj:" + identifier}}},
        {
            "tasks": {
                "7": {"label": "wj:another", "status": {"Done": {"result": "Success"}}}
            }
        },
    ])
    monkeypatch.setattr(jobs, "_snapshot", lambda _: next(states))

    async def observed(*_args: object) -> int:
        return await asyncio.sleep(0, result=0)

    monkeypatch.setattr(jobs, "_wait", observed)
    monkeypatch.setattr(
        sys, "argv", ["workstation-job", "--config", str(config), "wait", identifier]
    )
    with pytest.raises(ValueError, match="no longer belongs"):
        jobs.main()


def test_nested_durable_submission_refused(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """A job cannot deadlock by submitting into its own durable queue."""
    monkeypatch.setenv("WORKSTATION_JOB_ID", "owned-outer-job")
    with pytest.raises(ValueError, match="Nested durable submissions"):
        jobs._submit({"stateDirectory": str(tmp_path)}, "unused", Namespace())


def test_running_only_crash_pauses_future_admission(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """A surviving worker cannot overlap new work after a running-only crash."""
    state = {
        "groups": {"bounded": {"status": "Running"}},
        "tasks": {"1": {"group": "bounded", "status": {"Done": {"result": "Killed"}}}},
    }
    previous = {
        "groups": {"bounded": {"status": "Running"}},
        "tasks": {"1": {"status": {"Running": {}}}},
    }
    commands = []
    monkeypatch.setattr(jobs, "_snapshot", lambda _: state)
    monkeypatch.setattr(jobs, "_native", lambda _, *args: commands.append(args))
    jobs._recover_queued(
        {"stateDirectory": str(tmp_path), "profiles": {"bounded": {}}}, previous
    )
    assert commands == [("pause", "--group", "bounded", "--wait")]
    assert jobs._read(tmp_path / "queue-health.json")["needsReconciliation"]


def test_missing_process_identity_is_not_a_live_worker(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """An already exited payload with an empty start token cannot block recovery."""
    directory = tmp_path / "jobs" / ("c" * 32)
    directory.mkdir(parents=True)
    jobs._save(
        directory / "result.json",
        {"pid": 999999999, "processIdentity": "", "drained": False},
    )
    monkeypatch.setattr(jobs, "_process_identity", lambda *_: "")
    monkeypatch.setattr(jobs.platform, "system", lambda: "Linux")
    jobs._check_interrupted({"stateDirectory": str(tmp_path)})


def test_host_compiler_policy_and_explicit_environment_precedence(
    tmp_path: Path,
) -> None:
    """Host defaults apply to Nix and compilers without overriding opted-in values."""
    recipe = {
        "id": "fixture",
        "config": {
            "path": "/tools",
            "compilerCores": 12,
            "nixSettings": {"cores": 12, "max-jobs": "auto", "eval-cores": 6},
        },
        "environment": {
            "PATH": "/fixture",
            "NIX_BUILD_CORES": "3",
            "CARGO_BUILD_JOBS": "2",
            "NIX_CONFIG": "cores = 3\n",
        },
    }
    actual = jobs._execution_environment(recipe, tmp_path)
    assert actual["NIX_BUILD_CORES"] == "3"
    assert actual["CARGO_BUILD_JOBS"] == "2"
    assert actual["CMAKE_BUILD_PARALLEL_LEVEL"] == "12"
    assert actual["NIX_CONFIG"].splitlines().count("cores = 3") == 1
    assert "cores = 12" not in actual["NIX_CONFIG"]
    assert "max-jobs = auto" in actual["NIX_CONFIG"]
    assert "eval-cores = 6" in actual["NIX_CONFIG"]
    recipe["config"]["compilerCores"] = 0
    recipe["environment"] = {}
    assert "CARGO_BUILD_JOBS" not in jobs._execution_environment(recipe, tmp_path)


def test_declared_modes_route_custom_names_and_native_daemon_access() -> None:
    """Daemon capability works on native hosts and custom names retain their mode."""
    native = {"profiles": {"bounded": {"backend": "darwin", "allowDaemon": True}}}
    args = Namespace(profile="auto", requires_daemon=True)
    assert jobs._select_profile(native, args) == "bounded"
    cfg = {
        "profiles": {
            "shared": {"executionMode": "daemon", "allowDaemon": True},
            "quick": {
                "executionMode": "feedback",
                "allowDaemon": False,
                "minimumMiB": 512,
                "maximumMiB": 1024,
                "maximumSeconds": 30,
            },
            "bounded": {"allowDaemon": False},
        }
    }
    assert jobs._select_profile(cfg, args) == "shared"
    args = Namespace(profile="auto", requires_daemon=False, memory_mib=512, timeout=20)
    assert jobs._select_profile(cfg, args) == "quick"
    args = Namespace(profile="bounded", requires_daemon=True)
    with pytest.raises(jobs.JobError):
        jobs._select_profile(cfg, args)


@pytest.mark.parametrize(
    ("pages", "expected"),
    [
        (
            "Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages free: 3.\nPages inactive: 2.\nPages speculative: 1.\n",
            6 * 16384,
        ),
        ("unrecognized page-size header\nPages free: 3.\n", 0),
    ],
)
def test_native_admission_requires_known_page_size(
    monkeypatch: MonkeyPatch, pages: str, expected: int
) -> None:
    """Unknown native accounting must refuse capacity rather than guessing units."""
    replies = iter(["1\n", pages])
    monkeypatch.setattr(jobs.platform, "system", lambda: "Darwin")
    monkeypatch.setattr(
        jobs.subprocess, "check_output", lambda *_args, **_kwargs: next(replies)
    )
    assert jobs._available() == expected


@pytest.mark.parametrize(
    ("lower", "upper", "fixed", "mode"),
    [
        (None, 256, None, "bounded"),
        (64, None, None, "bounded"),
        (64, 256, 256, "bounded"),
        (0, 256, None, "bounded"),
        (256, 64, None, "bounded"),
        (64, 1024, None, "bounded"),
        (64, 256, None, "feedback"),
        (64, 256, None, "daemon"),
    ],
)
def test_elastic_contract_rejects_invalid_placement(
    tmp_path: Path, lower: int | None, upper: int | None, fixed: int | None, mode: str
) -> None:
    """Invalid ranges never reach native submission or daemon promotion."""
    cfg = {
        "stateDirectory": str(tmp_path),
        "profiles": {
            mode: {
                "backend": "systemd",
                "executionMode": mode,
                "memoryMiB": 256,
                "minimumMiB": 64,
                "maximumMiB": 512,
                "maximumSeconds": 1200,
            }
        },
    }
    args = Namespace(
        command=["true"],
        profile=mode,
        memory_mib=fixed,
        memory_min_mib=lower,
        memory_max_mib=upper,
        timeout=10,
    )
    with pytest.raises(ValueError, match=r"pair|profile|range"):
        jobs._submit(cfg, "unused", args)


def test_elastic_auto_range_does_not_select_feedback() -> None:
    """A complete range remains bounded even when its endpoints fit tiny work."""
    args = Namespace(
        profile="auto",
        requires_daemon=False,
        memory_mib=None,
        memory_min_mib=1024,
        memory_max_mib=2048,
        timeout=20,
    )
    assert (
        jobs._select_profile({"profiles": {"bounded": {}, "feedback": {}}}, args)
        == "bounded"
    )


@pytest.mark.parametrize("cancel", [False, True])
def test_stalled_memory_sampler_respects_deadline_and_cancel(
    monkeypatch: MonkeyPatch, cancel: bool
) -> None:
    """A stalled native sampler cannot strand a child or block signal callbacks."""

    async def exercise() -> None:
        cancelled = asyncio.Event()
        children = []
        original = asyncio.create_subprocess_exec

        async def spawn(*args: str, **kwargs: object) -> asyncio.subprocess.Process:
            assert kwargs == {
                "stdout": asyncio.subprocess.PIPE,
                "stderr": asyncio.subprocess.DEVNULL,
                "start_new_session": True,
            }
            process = await original(
                *args,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
                start_new_session=True,
            )
            children.append(process)
            if cancel:
                asyncio.get_running_loop().call_soon(cancelled.set)
            return process

        monkeypatch.setattr(jobs.asyncio, "create_subprocess_exec", spawn)
        with pytest.raises(TimeoutError):
            await jobs._memory_sample(
                [sys.executable, "-c", "import signal;signal.pause()"],
                cancelled,
                30 if cancel else 0.05,
            )
        assert len(children) == 1
        assert children[0].returncode is not None

    asyncio.run(exercise())


def test_native_cold_start_activates_aggregate_before_capacity(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """The first worker can discover a cgroup before any payload has started."""
    calls = []
    cfg = {
        "profiles": {"bounded": {"backend": "systemd"}},
        "systemctl": "manager",
        "memoryController": "controller",
        "reserveMiB": 512,
    }
    recipe = {"config": cfg, "profile": "bounded", "memoryMiB": 64, "timeout": 30}
    jobs._save(tmp_path / "memory-allocation.json", {"grantMiB": 64})
    monkeypatch.setattr(
        jobs.subprocess, "run", lambda command, **_: calls.append(command)
    )
    monkeypatch.setattr(
        jobs.subprocess,
        "check_output",
        lambda command, **_: calls.append(command) or "/workload",
    )

    async def spawn(*command: str, **_kwargs: object) -> SimpleNamespace:  # ruff: ignore[unused-async] - native process fixture protocol
        calls.append(command)

        async def wait() -> int:  # ruff: ignore[unused-async] - native process fixture protocol
            return 0

        return SimpleNamespace(returncode=0, wait=wait)

    monkeypatch.setattr(jobs.asyncio, "create_subprocess_exec", spawn)

    async def exercise() -> None:
        assert (
            await jobs._admit_native(
                recipe, tmp_path, asyncio.Event(), time.monotonic()
            )
            == 64
        )

    asyncio.run(exercise())
    assert calls[0][2] == "start"
    assert calls[1][2] == "show"
    assert calls[2][0:2] == ("controller", "admit")


def test_native_cleanup_permission_error_keeps_terminal_receipt(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """A denied cleanup signal must not strand an executing receipt."""
    original_killpg = os.killpg
    observed = set()

    def denied(group: int, sig: int) -> None:
        if sig != 0:
            observed.add(group)
            raise PermissionError(1, "fixture permission denied")
        original_killpg(group, sig)

    def invalid(_pid: int) -> int:
        message = "fixture invalid accounting"
        raise ValueError(message)

    monkeypatch.setattr(jobs.os, "killpg", denied)
    monkeypatch.setattr(jobs, "_group_usage", invalid)
    try:
        receipt = _native_sampling_child(tmp_path, monkeypatch, expected_drained=False)
    finally:
        for group in observed:
            with contextlib.suppress(ProcessLookupError):
                original_killpg(group, signal.SIGKILL)
    assert receipt["phase"] == "supervision-error"
    assert receipt["exitCode"] == 1
    assert receipt["nativeCleanupErrorTypes"] == ["PermissionError"]


def test_growth_cleanup_denial_cannot_override_successful_native_payload(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """A drained Linux payload cannot certify an unresolved owned growth helper."""
    original_spawn = asyncio.create_subprocess_exec
    original_signals = {
        sig: signal.getsignal(sig)
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)
    }

    def deny() -> None:
        raise PermissionError

    async def unused_wait() -> int:  # ruff: ignore[unused-async] - synthetic helper lifecycle
        return 0

    growth = SimpleNamespace(returncode=None, terminate=deny, wait=unused_wait)

    async def spawn(*command: object, **kwargs: object) -> object:
        if command[0] == "fixture-controller":
            assert command[1] == "grow"
            return growth
        sink = kwargs["stdout"]
        assert isinstance(sink, int)
        return await original_spawn(
            sys.executable,
            "-c",
            "pass",
            cwd=tmp_path,
            start_new_session=True,
            stdin=asyncio.subprocess.DEVNULL,
            stdout=sink,
            stderr=asyncio.subprocess.STDOUT,
        )

    async def admit(*_args: object) -> int:  # ruff: ignore[unused-async] - admission is independently qualified
        return 256

    monkeypatch.setattr(jobs.asyncio, "create_subprocess_exec", spawn)
    monkeypatch.setattr(jobs, "_admit_native", admit)
    monkeypatch.setattr(jobs, "_process_identity", lambda *_: "fixture-birth")
    identifier = "growth-cleanup-fixture"
    jobs._save(
        tmp_path / "memory-allocation.json", {"sample": {"availableBytes": 1024**4}}
    )
    jobs._save(
        tmp_path / "native-resources.json",
        {
            "nativeResources": {
                "measurement": "kernel-at-unit-stop",
                "controlGroup": "/fixture/workstation-job-" + identifier + ".service",
                "scopeResult": "success",
            }
        },
    )
    recipe = {
        "id": identifier,
        "profile": "bounded",
        "memoryMiB": 256,
        "memoryRange": {"minimumMiB": 256, "maximumMiB": 512},
        "timeout": 30,
        "sourceReference": "immutable-growth-fixture",
        "environment": {},
        "command": [sys.executable, "-c", "pass"],
        "cwd": str(tmp_path),
        "python": sys.executable,
        "executor": "fixture-executor",
        "config": {
            "profiles": {"bounded": {"backend": "systemd"}},
            "reserveMiB": 1,
            "compilerCores": 8,
            "path": os.environ.get("PATH", ""),
            "memoryController": "fixture-controller",
            "bubblewrap": "fixture-bwrap",
            "systemdRun": "fixture-systemd-run",
            "systemctl": "fixture-systemctl",
        },
    }
    try:
        code = asyncio.run(jobs._supervise(recipe, tmp_path))
    finally:
        for sig, handler in original_signals.items():
            signal.signal(sig, handler)
    receipt = jobs._read(tmp_path / "result.json")
    assert code == receipt["exitCode"] == 1
    assert receipt["phase"] == "cleanup-error"
    assert receipt["drained"] is False
    assert receipt["nativeCleanupErrorTypes"] == ["PermissionError"]
