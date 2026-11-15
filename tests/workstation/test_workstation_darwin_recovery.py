"""Explicit recovery of an observed absent native post-spawn process group."""
# ruff: file-ignore[private-member-access]

import hashlib
import importlib.util
import json
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from _pytest.monkeypatch import MonkeyPatch

SOURCE = (
    Path(__file__).parents[2]
    / "modules/home/services/workstation-jobs-assets/workstation_job.py"
)
SPEC = importlib.util.spec_from_file_location("darwin_recovery_jobs", SOURCE)
assert SPEC
assert SPEC.loader
jobs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(jobs)


def fixture(tmp_path: Path, monkeypatch: MonkeyPatch) -> tuple[dict, Path, str]:
    """Model a native failed execution with its original durable bindings.

    Returns:
        Client configuration, the claimed job directory and reviewed executor hash.

    """
    identifier = "a" * 32
    directory = jobs._job_path(tmp_path, identifier)
    directory.mkdir(parents=True)
    jobs._claim_execution(directory)
    executor = tmp_path / "reviewed-runtime.py"
    executor.write_bytes(SOURCE.read_bytes())
    pin = hashlib.sha256(executor.read_bytes()).hexdigest()
    cfg = {"stateDirectory": str(tmp_path), "ps": "unused-fixture-ps"}
    jobs._save(directory / "execution.claim", {"pid": 4401, "lifecycleVersion": 2})
    jobs._save(directory / "submission.json", {"taskId": "17"})
    jobs._save(
        directory / "recipe.json",
        {
            "id": identifier,
            "profile": "bounded",
            "owner": "fixture-owner",
            "executor": str(executor),
            "sourceReference": "immutable-fixture-source",
            "config": {"profiles": {"bounded": {"backend": "darwin"}}},
        },
    )
    jobs._save(
        directory / "result.json",
        {
            "backend": "darwin",
            "lifecycleVersion": 2,
            "phase": "executing",
            "pid": 4402,
            "processIdentity": "old payload birth",
            "wrapperPid": 4401,
            "wrapperIdentity": "old wrapper birth",
            "drained": False,
        },
    )
    task = {"label": "wj:" + identifier, "status": {"Done": {"result": {"Failed": 1}}}}
    monkeypatch.setattr(jobs.platform, "system", lambda: "Darwin")
    monkeypatch.setattr(
        jobs, "_snapshot", lambda _: {"groups": {}, "tasks": {"17": task}}
    )

    def absent(*_args: int) -> None:
        raise ProcessLookupError(3, "fixture absent")

    monkeypatch.setattr(jobs.os, "kill", absent)
    monkeypatch.setattr(jobs.os, "killpg", absent)
    return cfg, directory, pin


def test_known_native_group_reconciles_failure_without_replay(
    tmp_path: Path, monkeypatch: MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    """Prove absence twice, preserve original receipts, retire only its gate."""
    cfg, directory, pin = fixture(tmp_path, monkeypatch)
    original = (directory / "result.json").read_bytes()
    claim = (directory / "execution.claim").read_bytes()
    jobs._reconcile(cfg, directory.name, reviewed_darwin_executor=pin)
    proof = json.loads(capsys.readouterr().out)
    assert proof["nativeResultPreserved"] == {"Failed": 1}
    assert proof["drained"] is True
    assert (directory / "result.json").read_bytes() == original
    assert (directory / "execution.claim").read_bytes() == claim
    assert jobs._drain_proof_valid(directory)
    jobs._check_pending_claims(cfg)
    assert not (tmp_path / "pending-claims" / (directory.name + ".json")).exists()
    with pytest.raises(jobs.JobError, match="already claimed"):
        jobs._claim_execution(directory)
    jobs._inspect(cfg, directory.name)
    observed = json.loads(capsys.readouterr().out)["jobs"][0]
    assert observed["receipt"]["phase"] == "interrupted"
    assert observed["receipt"]["exitCode"] == 1
    assert observed["receipt"]["drained"] is True
    assert observed["receipt"]["outputEOF"] is None
    # A certified past lifetime must not inspect an unrelated future ID reuse.
    monkeypatch.setattr(jobs.os, "kill", lambda *_: None)
    monkeypatch.setattr(jobs.os, "killpg", lambda *_: None)
    assert jobs._drain_proof_valid(directory)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("pid", None),
        ("pid", True),
        ("processIdentity", ""),
        ("phase", "preflight"),
        ("wrapperPid", 4403),
        ("backend", "systemd"),
        ("lifecycleVersion", 1),
    ],
)
def test_native_receipt_ownership_is_required(
    tmp_path: Path, monkeypatch: MonkeyPatch, field: str, value: object
) -> None:
    """Malformed or mismatched receipt ownership never becomes a drain proof."""
    cfg, directory, pin = fixture(tmp_path, monkeypatch)
    jobs._save(
        directory / "result.json",
        jobs._read(directory / "result.json") | {field: value},
    )
    with pytest.raises(jobs.JobError):
        jobs._reconcile(cfg, directory.name, reviewed_darwin_executor=pin)
    assert not (directory / "reconciliation.json").exists()


@pytest.mark.parametrize("status", ["Running", "Success", "wrong-label"])
def test_native_terminal_failure_is_required(
    tmp_path: Path, monkeypatch: MonkeyPatch, status: str
) -> None:
    """A running, successful or unrelated native task cannot certify this failure."""
    cfg, directory, pin = fixture(tmp_path, monkeypatch)
    state = jobs._snapshot(cfg)
    task = state["tasks"]["17"]
    if status == "Running":
        task["status"] = {"Running": {}}
    elif status == "Success":
        task["status"] = {"Done": {"result": "Success"}}
    else:
        task["label"] = "wj:" + "b" * 32
    monkeypatch.setattr(jobs, "_snapshot", lambda _: state)
    with pytest.raises(jobs.JobError):
        jobs._reconcile(cfg, directory.name, reviewed_darwin_executor=pin)
    assert not (directory / "reconciliation.json").exists()


@pytest.mark.parametrize("target", ["payload", "wrapper", "group"])
@pytest.mark.parametrize("denied", [False, True])
def test_live_or_uncertain_native_ids_are_refused(
    tmp_path: Path, monkeypatch: MonkeyPatch, target: str, *, denied: bool
) -> None:
    """Signal-zero success and EPERM both refuse recovery without sending a signal."""
    cfg, directory, pin = fixture(tmp_path, monkeypatch)
    selected = 4401 if target == "wrapper" else 4402

    def probe(pid: int, sig: int) -> None:
        assert sig == 0
        if pid != selected:
            raise ProcessLookupError(3, "fixture absent")
        if denied:
            raise PermissionError(1, "fixture denied")

    monkeypatch.setattr(jobs.os, "killpg" if target == "group" else "kill", probe)
    with pytest.raises(jobs.JobError):
        jobs._reconcile(cfg, directory.name, reviewed_darwin_executor=pin)
    assert not (directory / "reconciliation.json").exists()


@pytest.mark.parametrize("scenario", ["no-review", "wrong-review", "wrong-host"])
def test_native_executor_review_and_host_are_required(
    tmp_path: Path, monkeypatch: MonkeyPatch, scenario: str
) -> None:
    """Only explicit review of this executor on Darwin permits group observations."""
    cfg, directory, pin = fixture(tmp_path, monkeypatch)
    if scenario == "no-review":
        pin = None
    elif scenario == "wrong-review":
        pin = "f" * 64
    else:
        monkeypatch.setattr(jobs.platform, "system", lambda: "Linux")
    with pytest.raises(jobs.JobError):
        jobs._reconcile(cfg, directory.name, reviewed_darwin_executor=pin)
    assert not (directory / "reconciliation.json").exists()


@pytest.mark.parametrize("changed", ["terminal", "receipt"])
def test_native_recovery_rechecks_stable_inputs(
    tmp_path: Path, monkeypatch: MonkeyPatch, changed: str
) -> None:
    """An input change between the two native observations prevents proof publication."""
    cfg, directory, pin = fixture(tmp_path, monkeypatch)
    original_snapshot = jobs._snapshot
    calls = 0

    def snapshot(configuration: dict) -> dict:
        nonlocal calls
        calls += 1
        value = original_snapshot(configuration)
        if calls > 1:
            if changed == "terminal":
                value["tasks"]["17"]["status"] = {"Done": {"result": {"Failed": 2}}}
            else:
                jobs._save(
                    directory / "result.json",
                    jobs._read(directory / "result.json") | {"changed": True},
                )
        return value

    monkeypatch.setattr(jobs, "_snapshot", snapshot)
    with pytest.raises(jobs.JobError):
        jobs._reconcile(cfg, directory.name, reviewed_darwin_executor=pin)
    assert not (directory / "reconciliation.json").exists()


@pytest.mark.parametrize(
    "name",
    [
        "execution.claim",
        "recipe.json",
        "result.json",
        "submission.json",
        "native-resources.json",
    ],
)
def test_native_proof_binds_all_durable_inputs(
    tmp_path: Path, monkeypatch: MonkeyPatch, name: str
) -> None:
    """A proof cannot survive mutation of the claimed execution or observation."""
    cfg, directory, pin = fixture(tmp_path, monkeypatch)
    jobs._reconcile(cfg, directory.name, reviewed_darwin_executor=pin)
    target = directory / name
    jobs._save(target, jobs._read(target) | {"changed": True})
    assert not jobs._drain_proof_valid(directory)
