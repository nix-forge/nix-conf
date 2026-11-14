"""Real owned-process regressions for interrupted supervision and recovery."""
# Fault injection intentionally exercises private transaction boundaries.
# ruff: file-ignore[private-member-access, subprocess-without-shell-equals-true, magic-value-comparison]

import asyncio
import contextlib
import hashlib
import importlib.util
import json
import os
import select
import shutil
import signal
import subprocess  # ruff: ignore[suspicious-subprocess-import] - only owned fixture processes and native ps are executed
import sys
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from typing import Any

    from _pytest.monkeypatch import MonkeyPatch

SOURCE = (
    Path(__file__).parents[2]
    / "modules/home/services/workstation-jobs-assets/workstation_job.py"
)
SPEC = importlib.util.spec_from_file_location("workstation_fault_jobs", SOURCE)
assert SPEC
assert SPEC.loader
jobs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(jobs)


def _ready(descriptor: int) -> None:
    """Wait for an owned fixture's readiness event with one deadline."""
    assert select.select([descriptor], [], [], 5)[0], "Fixture never became ready"
    assert os.read(descriptor, 1) == b"R"


def _live_group(ps: str, group: int) -> bool:
    """Check live members, excluding already dead unreaped zombies.

    Returns:
        Whether the fixture group still contains a live process.

    """
    output = subprocess.check_output([ps, "-axo", "pgid=,stat="], text=True)
    return any(
        int(pgid) == group and not state.startswith("Z")
        for pgid, state in (line.split() for line in output.splitlines())
    )


def _cleanup_payload(directory: Path, ps: str, marker_name: str = "owned.json") -> None:
    """Signal only the recorded fixture group while its identity still matches."""
    marker = directory / marker_name
    if not marker.exists():
        return
    owned = json.loads(marker.read_text(encoding="utf-8"))
    if jobs._process_identity(owned["pid"], {"ps": ps}) == owned["identity"]:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(owned["pid"], signal.SIGKILL)


async def _normal_capacity(*_args: object) -> int:
    """Keep fault fixtures independent of native pressure.

    Returns:
        Ample fixture headroom; pressure behavior is exercised separately.

    """
    await asyncio.sleep(0)
    return 1024**4


def _fault_worker(directory: Path, fault: str, ps: str) -> None:
    """Run the real supervisor with one injected post-spawn infrastructure error."""
    descriptor = os.open(directory / "ready", os.O_RDWR | os.O_NONBLOCK)
    if fault == "claim":
        jobs._claim_execution(directory)
        os.write(descriptor, b"R")
        signal.pause()
        return
    original_spawn = jobs.asyncio.create_subprocess_exec
    original_identity = jobs._process_identity
    original_save = jobs._save
    triggered = False

    async def spawn(*args: object, **kwargs: object) -> object:
        process = await original_spawn(*args, **kwargs)
        original_save(
            directory / "owned.json",
            {
                "pid": process.pid,
                "identity": original_identity(process.pid, {"ps": ps}),
            },
        )
        await asyncio.to_thread(_ready, descriptor)
        return process

    def identity(pid: int, config: dict[str, object]) -> str:
        """Fail exactly once when reading the newly spawned payload identity.

        Returns:
            The native process start identity when the probe succeeds.

        Raises:
            OSError: The selected infrastructure fault is reached.

        """
        nonlocal triggered
        if fault == "identity" and pid != os.getpid() and not triggered:
            triggered = True
            message = "Injected post-spawn identity failure"
            raise OSError(message)
        return original_identity(pid, config)

    def save(path: Path, value: dict[str, object]) -> None:
        """Lose one executing receipt while permitting the final failure receipt.

        Raises:
            OSError: The selected persistence fault is reached.

        """
        nonlocal triggered
        if (
            fault == "persistence"
            and value.get("phase") == "executing"
            and not triggered
        ):
            triggered = True
            message = "Injected post-spawn receipt failure"
            raise OSError(message)
        original_save(path, value)

    async def usage(group: int, *_args: object, **_kwargs: object) -> int:
        """Read native RSS with one selected accounting outage.

        Returns:
            Resident bytes charged to the fixture process group.

        Raises:
            OSError: RSS accounting is unavailable.

        """
        await asyncio.sleep(0)
        nonlocal triggered
        if fault == "rss" and not triggered:
            triggered = True
            message = "Injected RSS read failure"
            raise OSError(message)
        output = await asyncio.to_thread(
            subprocess.check_output, [ps, "-axo", "pid=,pgid=,rss="], text=True
        )
        return sum(
            int(rss) * 1024
            for _, pgid, rss in (line.split() for line in output.splitlines())
            if int(pgid) == group
        )

    jobs.asyncio.create_subprocess_exec = spawn
    vars(jobs).update(
        _process_identity=identity,
        _save=save,
        _available=lambda: 1024**4,
        _group_usage=usage,
        _darwin_available=_normal_capacity,
    )
    payload = (
        "import os,signal; "
        "fd=os.open('ready',os.O_WRONLY); os.write(fd,b'R'); os.close(fd); "
        "signal.pause()"
    )
    recipe: dict[str, Any] = {
        "id": "fault-fixture",
        "profile": "bounded",
        "memoryMiB": 256,
        "timeout": 2,
        "sourceReference": "immutable-fault-fixture",
        "environment": {},
        "command": [sys.executable, "-c", payload],
        "cwd": str(directory),
        "config": {
            "profiles": {"bounded": {"backend": "darwin"}},
            "reserveMiB": 1,
            "compilerCores": 2,
            "path": os.environ.get("PATH", ""),
            "ps": ps,
        },
    }
    if fault == "systemd":
        _systemd_fixture(recipe, directory, ps)
    try:
        code = asyncio.run(jobs._supervise(recipe, directory))
        original_save(directory / "worker-result.json", {"exitCode": code})
    finally:
        os.close(descriptor)


def _systemd_fixture(recipe: dict[str, Any], directory: Path, ps: str) -> None:
    """Replace native commands with an owned launcher that leaves detached work."""
    launcher = directory / "fake-systemd-run"
    launcher.write_text(
        f"#!{sys.executable}\n"
        "import json,os,subprocess,sys\n"
        "from pathlib import Path\n"
        "child=subprocess.Popen([sys.executable,'-c','import signal;signal.pause()'],"
        "start_new_session=True,stdin=subprocess.DEVNULL,"
        "stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)\n"
        f"identity=subprocess.check_output([{ps!r},'-p',str(child.pid),"
        "'-o','lstart='],text=True).strip()\n"
        "Path('detached.json').write_text(json.dumps({'pid':child.pid,'identity':identity}))\n"
        "fd=os.open('ready',os.O_WRONLY);os.write(fd,b'R');os.close(fd)\n",
        encoding="utf-8",
    )
    launcher.chmod(0o700)
    recipe["python"] = sys.executable
    recipe["executor"] = str(SOURCE)
    recipe["config"]["profiles"]["bounded"]["backend"] = "systemd"
    recipe["config"].update(
        systemdRun=str(launcher),
        bubblewrap=sys.executable,
        systemctl=str(directory / "missing-systemctl"),
    )


@pytest.mark.parametrize("fault", ["rss", "identity", "persistence"])
def test_supervision_fault_drains_real_payload(tmp_path: Path, fault: str) -> None:
    """Infrastructure errors fail promptly and cannot orphan the owned payload."""
    ps = shutil.which("ps")
    if ps is None or not hasattr(os, "mkfifo"):
        pytest.skip("Native ps and FIFO readiness are required")
    os.mkfifo(tmp_path / "ready", 0o600)
    process = subprocess.Popen(
        [sys.executable, str(Path(__file__).resolve()), str(tmp_path), fault, ps],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=12)
        assert process.returncode == 0, stdout + stderr
        result = json.loads(
            (tmp_path / "worker-result.json").read_text(encoding="utf-8")
        )
        assert result["exitCode"] != 0
        receipt = json.loads((tmp_path / "result.json").read_text(encoding="utf-8"))
        assert receipt["phase"] == "supervision-error"
        assert receipt["exitCode"] != 0
        assert receipt["drained"] is True
        owned = json.loads((tmp_path / "owned.json").read_text(encoding="utf-8"))
        assert not _live_group(ps, owned["pid"])
    finally:
        if process.poll() is None:
            process.kill()
        _cleanup_payload(tmp_path, ps)
        process.communicate(timeout=5)


def test_systemd_launcher_eof_does_not_prove_native_drain(tmp_path: Path) -> None:
    """Launcher success cannot certify a detached unit without native stop proof."""
    ps = shutil.which("ps")
    if ps is None or not hasattr(os, "mkfifo"):
        pytest.skip("Native ps and FIFO readiness are required")
    os.mkfifo(tmp_path / "ready", 0o600)
    process = subprocess.Popen(
        [sys.executable, str(Path(__file__).resolve()), str(tmp_path), "systemd", ps],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=12)
        assert process.returncode == 0, stdout + stderr
        owned = json.loads((tmp_path / "detached.json").read_text(encoding="utf-8"))
        assert _live_group(ps, owned["pid"]), "Fixture must leave native work alive"
        result = json.loads(
            (tmp_path / "worker-result.json").read_text(encoding="utf-8")
        )
        assert result["exitCode"] != 0
        receipt = json.loads((tmp_path / "result.json").read_text(encoding="utf-8"))
        assert receipt["phase"] != "succeeded"
        assert receipt["exitCode"] != 0
        assert receipt["drained"] is False
        assert not (tmp_path / "native-resources.json").exists()
    finally:
        if process.poll() is None:
            process.kill()
        _cleanup_payload(tmp_path, ps, "detached.json")
        _cleanup_payload(tmp_path, ps)
        process.communicate(timeout=5)


@pytest.mark.parametrize("receipt", [None, {"drained": False, "pid": 999999999}])
def test_v2_unresolved_claim_blocks_resume_after_worker_disappears(
    tmp_path: Path, monkeypatch: MonkeyPatch, receipt: dict[str, object] | None
) -> None:
    """A lost lifecycle receipt stays ambiguous even when recorded PIDs are gone."""
    directory = jobs._job_path(tmp_path, "a" * 32)
    directory.mkdir(parents=True)
    jobs._claim_execution(directory)
    assert jobs._read(directory / "execution.claim")["lifecycleVersion"] == 2
    if receipt is not None:
        jobs._save(directory / "result.json", receipt)
    commands = []
    monkeypatch.setattr(jobs, "_process_identity", lambda *_: "")

    async def zero(*_args: object, **_kwargs: object) -> int:
        await asyncio.sleep(0)
        return 0

    monkeypatch.setattr(jobs, "_group_usage", zero)
    monkeypatch.setattr(jobs, "_native", lambda _, *args: commands.append(args))
    with pytest.raises(jobs.JobError, match="reconciliation"):
        jobs._resume({"stateDirectory": str(tmp_path), "profiles": {"bounded": {}}})
    assert not commands


def test_legacy_missing_receipt_remains_compatible(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Old claims keep their previous recovery behavior during staged upgrades."""
    directory = jobs._job_path(tmp_path, "b" * 32)
    directory.mkdir(parents=True)
    jobs._save(directory / "execution.claim", {"pid": 999999999, "time": 0})
    commands = []
    monkeypatch.setattr(jobs, "_native", lambda _, *args: commands.append(args))
    jobs._resume({"stateDirectory": str(tmp_path), "profiles": {"bounded": {}}})
    assert commands == [("start", "--group", "bounded")]


def test_killed_worker_before_first_receipt_blocks_resume(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """A native SIGKILL after durable claim cannot silently reopen admission."""
    ps = shutil.which("ps")
    if ps is None or not hasattr(os, "mkfifo"):
        pytest.skip("Native ps and FIFO readiness are required")
    directory = jobs._job_path(tmp_path, "c" * 32)
    directory.mkdir(parents=True)
    os.mkfifo(directory / "ready", 0o600)
    descriptor = os.open(directory / "ready", os.O_RDWR | os.O_NONBLOCK)
    process = subprocess.Popen(
        [sys.executable, str(Path(__file__).resolve()), str(directory), "claim", ps],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        _ready(descriptor)
        process.kill()
        process.communicate(timeout=5)
        assert process.returncode == -signal.SIGKILL
        assert not (directory / "result.json").exists()
        commands = []
        monkeypatch.setattr(jobs, "_native", lambda _, *args: commands.append(args))
        with pytest.raises(jobs.JobError, match="reconciliation"):
            jobs._resume({"stateDirectory": str(tmp_path), "profiles": {"bounded": {}}})
        assert not commands
    finally:
        os.close(descriptor)
        if process.poll() is None:
            process.kill()
        process.communicate(timeout=5)


def _pending_claim(tmp_path: Path) -> tuple[dict[str, str], Path, Path]:
    """Create one durable claim in an otherwise isolated client state.

    Returns:
        Client configuration, job directory, and its pending marker.

    """
    directory = jobs._job_path(tmp_path, "d" * 32)
    directory.mkdir(parents=True)
    jobs._claim_execution(directory)
    marker = tmp_path / "pending-claims" / (directory.name + ".json")
    assert marker.exists()
    return {"stateDirectory": str(tmp_path)}, directory, marker


@pytest.mark.parametrize("status", ["Running", "Paused"])
@pytest.mark.parametrize("acknowledged", [True, False])
def test_pending_active_exact_label_preserves_admission(
    tmp_path: Path, monkeypatch: MonkeyPatch, status: str, acknowledged: bool
) -> None:
    """An active exact owner is accepted even before its submit ACK is saved."""
    cfg, directory, marker = _pending_claim(tmp_path)
    if acknowledged:
        jobs._save(directory / "submission.json", {"taskId": "17"})
    monkeypatch.setattr(
        jobs,
        "_snapshot",
        lambda _: {
            "tasks": {"17": {"label": "wj:" + directory.name, "status": {status: {}}}}
        },
    )
    jobs._check_pending_claims(cfg)
    assert marker.exists(), "An active claim must remain pending until drainage"


@pytest.mark.parametrize("receipt", [None, {"drained": False}])
def test_pending_terminal_unresolved_receipt_blocks_admission(
    tmp_path: Path, monkeypatch: MonkeyPatch, receipt: dict[str, object] | None
) -> None:
    """Native terminal state cannot certify a missing or undrained receipt."""
    cfg, directory, marker = _pending_claim(tmp_path)
    jobs._save(directory / "submission.json", {"taskId": "17"})
    if receipt is not None:
        jobs._save(directory / "result.json", receipt)
    monkeypatch.setattr(
        jobs,
        "_snapshot",
        lambda _: {
            "tasks": {
                "17": {
                    "label": "wj:" + directory.name,
                    "status": {"Done": {"result": "Killed"}},
                }
            }
        },
    )
    with pytest.raises(jobs.JobError, match="blocks new admission"):
        jobs._check_pending_claims(cfg)
    assert marker.exists()


def test_pending_drained_receipt_retires_only_its_marker(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """A completed drain retires the admission gate while retaining its evidence."""
    cfg, directory, marker = _pending_claim(tmp_path)
    receipt = {"drained": True, "phase": "failed", "exitCode": 1}
    jobs._save(directory / "result.json", receipt)
    claim = (directory / "execution.claim").read_bytes()
    monkeypatch.setattr(jobs, "_snapshot", lambda _: {"tasks": {}})
    jobs._check_pending_claims(cfg)
    assert not marker.exists()
    assert jobs._read(directory / "result.json") == receipt
    assert (directory / "execution.claim").read_bytes() == claim


def test_pending_recycled_native_id_blocks_admission(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    """Another active task sharing a numeric ID cannot stand in for the owner."""
    cfg, directory, marker = _pending_claim(tmp_path)
    jobs._save(directory / "submission.json", {"taskId": "17"})
    monkeypatch.setattr(
        jobs,
        "_snapshot",
        lambda _: {
            "tasks": {"17": {"label": "wj:" + "e" * 32, "status": {"Running": {}}}}
        },
    )
    with pytest.raises(jobs.JobError, match="blocks new admission"):
        jobs._check_pending_claims(cfg)
    assert marker.exists()


@pytest.mark.parametrize("tampered", ["execution.claim", "native-resources.json"])
def test_drain_proof_rejects_modified_claim_or_resource_receipt(
    tmp_path: Path, monkeypatch: MonkeyPatch, tampered: str
) -> None:
    """Reconciliation authorizes only the exact preserved execution evidence."""
    _, directory, _ = _pending_claim(tmp_path)
    group = "/fixture/workstation-job-" + directory.name + ".service"
    resources = directory / "native-resources.json"
    jobs._save(
        resources,
        {
            "nativeResources": {
                "measurement": "kernel-at-unit-stop",
                "controlGroup": group,
            }
        },
    )
    jobs._save(
        directory / "reconciliation.json",
        {
            "id": directory.name,
            "drained": True,
            "claimSha256": hashlib.sha256(
                (directory / "execution.claim").read_bytes()
            ).hexdigest(),
            "resourcesSha256": hashlib.sha256(resources.read_bytes()).hexdigest(),
        },
    )
    original_exists = Path.exists
    expected_group = Path("/sys/fs/cgroup") / group.lstrip("/")
    monkeypatch.setattr(
        Path,
        "exists",
        lambda path: False if path == expected_group else original_exists(path),
    )
    assert jobs._drain_proof_valid(directory)
    target = directory / tampered
    changed = jobs._read(target)
    changed["unexpectedChange"] = True
    jobs._save(target, changed)
    assert not jobs._drain_proof_valid(directory)


@pytest.mark.parametrize(
    "missing",
    [set(), {"memory.peak"}, {"memory.swap.peak"}, {"memory.peak", "memory.swap.peak"}],
)
def test_missing_optional_group_pressure_preserves_kernel_stop_receipt(
    tmp_path: Path, monkeypatch: MonkeyPatch, missing: set[str]
) -> None:
    """Kernels without PSI still retain authoritative peak and stop counters."""
    identifier = "f" * 32
    jobs._save(tmp_path / "recipe.json", {"id": identifier})
    group = "/fixture/workstation-job-" + identifier + ".service"
    kernel = Path("/sys/fs/cgroup") / group.lstrip("/")
    values = {
        Path("/proc/self/cgroup"): "0::" + group + "\n",
        kernel / "memory.peak": "4096\n",
        kernel / "memory.swap.peak": "0\n",
        kernel / "memory.events": "oom 1\noom_kill 1\n",
    }
    original_read = Path.read_text

    def kernel_read(
        path: Path,
        encoding: str | None = None,
        errors: str | None = None,
        newline: str | None = None,
    ) -> str:
        """Expose fixture counters while modeling an absent optional PSI file.

        Returns:
            Fixture kernel text or the unchanged ordinary file contents.

        Raises:
            FileNotFoundError: The optional pressure interface is unavailable.

        """
        if path == kernel / "memory.pressure" or (
            path.parent == kernel and path.name in missing
        ):
            raise FileNotFoundError(path)
        return (
            values[path]
            if path in values
            else original_read(path, encoding=encoding, errors=errors, newline=newline)
        )

    monkeypatch.setattr(Path, "read_text", kernel_read)
    monkeypatch.setenv("SERVICE_RESULT", "oom-kill")
    jobs._collect_resources(tmp_path)
    native = jobs._read(tmp_path / "native-resources.json")["nativeResources"]
    assert native["measurement"] == "kernel-at-unit-stop"
    assert native["controlGroup"] == group
    assert native["MemoryPeak"] == (None if "memory.peak" in missing else 4096)
    assert native["MemorySwapPeak"] == (None if "memory.swap.peak" in missing else 0)
    assert native["memoryEvents"] == {"oom": 1, "oom_kill": 1}
    assert native["scopeResult"] == "oom-kill"
    assert native["memoryPressure"] is None


def test_missing_host_psi_is_unknown(monkeypatch: MonkeyPatch) -> None:
    """Missing Linux PSI is unknown telemetry rather than a fatal admission error."""
    original_read = Path.read_text

    def kernel_read(
        path: Path,
        encoding: str | None = None,
        errors: str | None = None,
        newline: str | None = None,
    ) -> str:
        """Model a kernel without the host pressure interface.

        Returns:
            Ordinary file contents for unrelated reads.

        Raises:
            FileNotFoundError: Host PSI is not exposed by this kernel.

        """
        if path == Path("/proc/pressure/memory"):
            raise FileNotFoundError(path)
        return original_read(path, encoding=encoding, errors=errors, newline=newline)

    monkeypatch.setattr(Path, "read_text", kernel_read)
    monkeypatch.setattr(jobs.platform, "system", lambda: "Linux")
    assert jobs._host_memory_pressure() is None


@pytest.mark.parametrize(
    "scenario",
    [
        "absent",
        "live-launcher",
        "active-unit",
        "live-wrapper",
        "live-cgroup",
        "no-opt-in",
        "queued-other",
        "active-other",
        "controller-survives",
    ],
)
def test_generic_preflight_reconcile_requires_native_quiescence(  # ruff: ignore[too-many-statements, too-many-locals] - one mocked recovery transaction exercises all fail-closed boundaries
    tmp_path: Path, monkeypatch: MonkeyPatch, scenario: str
) -> None:
    """Only confirmed absence can resolve a generic worker's lost preflight."""
    cfg, directory, _ = _pending_claim(tmp_path)
    controller = "workstation-jobs-audit-" + "a" * 32 + ".service"
    cfg.update(systemctl="fixture-systemctl", ps="fixture-ps", ownerUnit=controller)
    identifier = directory.name
    unit = "workstation-job-" + identifier + ".service"
    parent = "/fixture-user/workstation-jobs-workload.slice"
    group = parent + "/" + unit
    jobs._save(directory / "submission.json", {"taskId": "17"})
    jobs._save(
        directory / "recipe.json",
        {
            "profile": "bounded",
            "config": {"profiles": {"bounded": {"backend": "systemd"}}},
        },
    )
    jobs._save(
        directory / "result.json",
        {
            "phase": "preflight",
            "drained": False,
            "wrapperPid": 999999999,
            "wrapperIdentity": "fixture-old-start",
        },
    )
    original_receipt = (directory / "result.json").read_bytes()
    monkeypatch.setattr(
        jobs,
        "_process_identity",
        lambda *_: "fixture-old-start" if scenario == "live-wrapper" else "",
    )
    tasks = {
        "17": {"label": "wj:" + identifier, "status": {"Done": {"result": "Killed"}}}
    }
    if scenario in {"queued-other", "active-other"}:
        tasks["18"] = {
            "label": "wj:" + "e" * 32,
            "status": {"Queued" if scenario == "queued-other" else "Running": {}},
        }
    monkeypatch.setattr(jobs, "_snapshot", lambda _: {"tasks": tasks})
    queries = []
    unit_query = [
        "fixture-systemctl",
        "--user",
        "show",
        unit,
        "--property=LoadState",
        "--property=ActiveState",
    ]
    process_query = ["fixture-ps", "-ww", "-axo", "args="]
    parent_query = [
        "fixture-systemctl",
        "--user",
        "show",
        "workstation-jobs-workload.slice",
        "--property=ControlGroup",
        "--value",
    ]
    controller_query = [
        "fixture-systemctl",
        "--user",
        "show",
        controller,
        "--property=ControlGroup",
        "--value",
    ]
    controller_group = "/fixture-user/" + controller
    stop_command = ["fixture-systemctl", "--user", "stop", controller]
    start_slice = [
        "fixture-systemctl",
        "--user",
        "start",
        "workstation-jobs-workload.slice",
    ]

    def native_query(command: list[str], **_kwargs: object) -> str:
        """Return only the explicitly modeled manager and launcher observations.

        Returns:
            The requested fixture state without executing a native command.

        """
        queries.append(command)
        if command == controller_query:
            return controller_group + "\n"
        if command == unit_query:
            return (
                "LoadState=loaded\nActiveState=active\n"
                if scenario == "active-unit"
                else "LoadState=not-found\nActiveState=inactive\n"
            )
        if command == process_query:
            return "systemd-run --unit " + unit if scenario == "live-launcher" else ""
        assert command == parent_query
        return parent + "\n"

    def native_stop(command: list[str], **kwargs: object) -> None:
        """Record only a checked stop of this fixture's exact controller."""
        assert command in (stop_command, start_slice)
        assert kwargs == {"check": True, "timeout": 15}
        queries.append(command)

    original_exists = Path.exists
    expected_group = Path("/sys/fs/cgroup") / group.lstrip("/")
    expected_controller = Path("/sys/fs/cgroup") / controller_group.lstrip("/")
    monkeypatch.setattr(
        Path,
        "exists",
        lambda path: (
            scenario == "live-cgroup"
            if path == expected_group
            else scenario == "controller-survives"
            if path == expected_controller
            else original_exists(path)
        ),
    )
    monkeypatch.setattr(jobs.subprocess, "check_output", native_query)
    monkeypatch.setattr(jobs.subprocess, "run", native_stop)
    if scenario == "absent":
        jobs._reconcile(cfg, identifier, drain_idle_controller=True)
        native = jobs._read(directory / "native-resources.json")["nativeResources"]
        assert native == {
            "measurement": "manager-confirmed-absent",
            "controlGroup": group,
            "MemoryPeak": None,
            "MemorySwapPeak": None,
            "memoryEvents": None,
            "memoryPressure": None,
            "scopeResult": None,
        }
        assert jobs._drain_proof_valid(directory)
        assert (
            jobs._read(directory / "reconciliation.json")["nativeResultPreserved"]
            == "Killed"
        )
        assert queries == [
            controller_query,
            stop_command,
            unit_query,
            process_query,
            unit_query,
            start_slice,
            parent_query,
        ]
    else:
        with pytest.raises(
            jobs.JobError,
            match=r"still exists|quiescence|cgroup still exists|No native stop evidence|unfinished work|has not drained",
        ):
            jobs._reconcile(
                cfg,
                identifier,
                **({} if scenario == "no-opt-in" else {"drain_idle_controller": True}),
            )
        assert not (directory / "reconciliation.json").exists()
        assert not (directory / "native-resources.json").exists()
        if scenario in {"live-wrapper", "no-opt-in", "queued-other", "active-other"}:
            assert not queries
    assert (directory / "result.json").read_bytes() == original_receipt


if __name__ == "__main__":
    _fault_worker(Path(sys.argv[1]), sys.argv[2], sys.argv[3])
