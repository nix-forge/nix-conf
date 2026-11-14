"""Durable, owner-labelled Pueue jobs; native execution owns containment."""
# Explicit subprocess argv implements this CLI; no shell expression is assembled.
# ruff: file-ignore[subprocess-without-shell-equals-true]

import argparse
import asyncio
import contextlib
import fcntl
import hashlib
import json
import operator
import os
import platform
import re
import shlex
import signal
import socket
import subprocess  # ruff: ignore[suspicious-subprocess-import] - this program executes explicit user commands
import sys
import time
import uuid
from collections.abc import Generator, Sequence  # ruff: ignore[typing-only-standard-library-import] - runtime annotations
from pathlib import Path
from typing import Any, NoReturn

Json = dict[str, Any]
MIB = 1024**2
CANCELLED_EXIT = 130
ADMISSION_EXPIRED_EXIT = 124
LIFECYCLE_VERSION = 2
HISTORY_LIMIT = 100
# Pueue persists the client environment. Never inherit a whole agent environment.
ENVIRONMENT = {
    "HOME",
    "USER",
    "LOGNAME",
    "PATH",
    "LANG",
    "LC_ALL",
    "TMPDIR",
    "XDG_RUNTIME_DIR",
    "DBUS_SESSION_BUS_ADDRESS",
    "SSH_AUTH_SOCK",
    "CODEX_THREAD_ID",
    "NIX_SSL_CERT_FILE",
    "SSL_CERT_FILE",
    "CMAKE_BUILD_PARALLEL_LEVEL",
    "CARGO_BUILD_JOBS",
    "MAKEFLAGS",
}


class JobError(ValueError):
    """The submitted job or recovery request cannot safely proceed."""


def _fail(message: str) -> NoReturn:
    raise JobError(message)


def _read(path: str | Path) -> Json:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _save(path: str | Path, value: Json) -> None:
    path = Path(path)
    temporary = path.with_suffix(".tmp")
    with temporary.open("w", encoding="utf-8") as stream:
        json.dump(value, stream, sort_keys=True)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)
    descriptor = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _native(cfg: Json, *args: str | int, capture: bool = True) -> str:
    return (
        subprocess.run(
            [cfg["pueue"], "-c", cfg["pueueConfig"], *map(str, args)],
            text=True,
            capture_output=capture,
            check=True,
        ).stdout
        or ""
    )


def _snapshot(cfg: Json) -> Json:
    return json.loads(_native(cfg, "status", "--json"))


def _terminal(task: Json) -> Json | None:
    status = task.get("status", {})
    return status.get("Done") if isinstance(status, dict) else None


def _filtered_environment(extra: Sequence[str] = ()) -> dict[str, str]:
    for name in extra:
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
            _fail("Invalid environment variable name")
    return {
        key: value
        for key, value in os.environ.items()
        if key in ENVIRONMENT | set(extra)
    }


def _paths(cfg: Json) -> Path:
    root = Path(cfg["stateDirectory"])
    root.mkdir(parents=True, mode=0o700, exist_ok=True)
    root.chmod(0o700)
    (root / "jobs").mkdir(mode=0o700, exist_ok=True)
    return root


@contextlib.contextmanager
def _locked(root: Path) -> Generator[None]:
    with (root / "submit.lock").open("a", encoding="utf-8") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def _job_path(root: Path, identifier: str) -> Path:
    if not re.fullmatch(r"[0-9a-f]{32}", identifier):
        _fail("Use the stable workstation-job ID, not an arbitrary path")
    return root / "jobs" / identifier


def _root_store(cfg: Json, directory: Path, target: str, name: str) -> None:
    # Pin both the executor and configuration dependency graphs before queuing.
    match = re.match(r"(/nix/store/[^/]+)", str(Path(target).resolve()))
    if not match:
        _fail("Production jobs require an immutable Nix store runtime")
    subprocess.run(
        [
            cfg["nixStore"],
            "--add-root",
            str(directory / name),
            "--indirect",
            "--realise",
            match[1],
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def _mode(profile: Json, name: str) -> str:
    """Read the executor mode.

    Returns:
        The explicit mode or the legacy immutable configuration default.

    """
    return profile.get(
        "executionMode", name if name in {"feedback", "daemon"} else "bounded"
    )


def _allows_daemon(profile: Json, name: str) -> bool:
    """Describe actual daemon access.

    Returns:
        Whether the executor permits the shared daemon.

    """
    return profile.get(
        "allowDaemon",
        profile.get("backend") == "darwin" or _mode(profile, name) == "daemon",
    )


def _select_profile(cfg: Json, args: argparse.Namespace) -> str:
    """Route declared requirements without inspecting commands or retrying work.

    Returns:
        The concrete host profile to persist in the immutable recipe.

    """
    requires_daemon = getattr(args, "requires_daemon", False)
    if args.profile not in {None, "auto"}:
        if requires_daemon and not _allows_daemon(
            cfg["profiles"].get(args.profile, {}), args.profile
        ):
            _fail("--requires-daemon conflicts with a confined execution profile")
        return args.profile
    if requires_daemon:
        eligible = sorted(
            name
            for name, profile in cfg["profiles"].items()
            if _allows_daemon(profile, name)
        )
        if not eligible:
            _fail("This host has no execution profile supporting --requires-daemon")
        return "daemon" if "daemon" in eligible else eligible[0]
    if args.profile is None or getattr(args, "memory_min_mib", None) is not None:
        return "bounded"
    # Both declarations must opt into tiny, short work. Missing estimates use
    # bounded defaults; a large request never implicitly gains daemon access.
    if args.memory_mib is not None and args.timeout is not None:
        for name, feedback in sorted(cfg["profiles"].items()):
            if (
                _mode(feedback, name) == "feedback"
                and feedback["minimumMiB"] <= args.memory_mib <= feedback["maximumMiB"]
                and 1 <= args.timeout <= feedback["maximumSeconds"]
            ):
                return name
    return "bounded"


def _submit(cfg: Json, config_path: str, args: argparse.Namespace) -> None:  # ruff: ignore[complex-structure, too-many-branches, too-many-statements, too-many-locals] - one submission transaction
    if os.environ.get("WORKSTATION_JOB_ID"):
        _fail(
            "Nested durable submissions are forbidden; run inner checks in the current allocation"
        )
    root = _paths(cfg)
    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        _fail("A finite command is required")
    args.profile = _select_profile(cfg, args)
    if args.profile not in cfg["profiles"]:
        _fail("This host does not support that execution profile")
    profile = cfg["profiles"][args.profile]
    memory = profile["memoryMiB"] if args.memory_mib is None else args.memory_mib
    lower = getattr(args, "memory_min_mib", None)
    upper = getattr(args, "memory_max_mib", None)
    elastic = lower is not None or upper is not None
    if elastic:
        if lower is None or upper is None or args.memory_mib is not None:
            _fail("Supply a memory min/max pair without --memory-mib")
        if _mode(profile, args.profile) != "bounded":
            _fail("Elastic memory requires a bounded profile")
        if not profile["minimumMiB"] <= lower <= upper <= profile["maximumMiB"]:
            _fail("Memory range is outside the declared host profile")
        if profile["backend"] == "desktop" and (lower % 1024 or upper % 1024):
            _fail("Desktop memory requests must be whole GiB")
        memory = upper
    if not profile["minimumMiB"] <= memory <= profile["maximumMiB"]:
        _fail("Requested memory is outside the declared host profile")
    args.timeout = (
        min(1200, profile["maximumSeconds"]) if args.timeout is None else args.timeout
    )
    if not 1 <= args.timeout <= profile["maximumSeconds"]:
        _fail("Deadline is outside the declared host profile")
    if profile["backend"] == "desktop" and memory % 1024:
        _fail("Desktop memory requests must be whole GiB")
    identity = {"owner": args.owner, "key": args.key}
    specification = {
        **identity,
        "command": command,
        "cwd": str(Path(args.cwd).resolve(strict=True)),
        "profile": args.profile,
        "memoryMiB": memory,
        "timeout": args.timeout,
        "sourceReference": args.source,
        "environment": _filtered_environment(args.env),
    }
    if elastic:
        specification["memoryRange"] = {"minimumMiB": lower, "maximumMiB": upper}
    fingerprint = hashlib.sha256(
        json.dumps(specification, sort_keys=True).encode()
    ).hexdigest()
    with _locked(root):
        _check_pending_claims(cfg)
        if (root / "maintenance.json").exists():
            _fail("Queue update in progress; inspect doctor before retry")
        if (root / "queue-health.json").exists() and _read(
            root / "queue-health.json"
        ).get("needsReconciliation"):
            _fail(
                "Interrupted queue requires owner reconciliation before new submissions"
            )
        # Bounded per-request lookup. A durable hashed index avoids history replay.
        key = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
        index = root / f"request-{key}.json"
        if index.exists():
            recorded = _read(index)
            directory = _job_path(root, recorded["id"])
            recipe = _read(directory / "recipe.json")
            if recipe["fingerprint"] != fingerprint:
                _fail("Request key already belongs to a different immutable job")
        else:
            identifier = uuid.uuid4().hex
            directory = _job_path(root, identifier)
            directory.mkdir(mode=0o700)
            _root_store(cfg, directory, sys.argv[0], "executor-root")
            _root_store(cfg, directory, config_path, "configuration-root")
            recipe: Json = {
                **specification,
                "id": identifier,
                "fingerprint": fingerprint,
                "created": time.time(),
                "host": platform.node(),
                "config": cfg,
                "executor": str(Path(sys.argv[0]).resolve()),
                "python": sys.executable,
            }
            _save(directory / "recipe.json", recipe)
            _save(index, {"id": identifier})
        receipt_path = directory / "submission.json"
        receipt = _read(receipt_path) if receipt_path.exists() else {}
        if "taskId" not in receipt:
            matches = [
                str(i)
                for i, task in _snapshot(cfg)["tasks"].items()
                if task.get("label") == f"wj:{recipe['id']}"
            ]
            if len(matches) > 1:
                _fail("Ambiguous duplicate native jobs; reconciliation required")
            if matches:
                receipt = {"taskId": matches[0], "reconciled": time.time()}
            elif receipt.get("phase") == "submitting":
                _fail(
                    "Submission acknowledgment lost and no native record found; inspect before retry"
                )
            else:
                _save(receipt_path, {"phase": "submitting", "time": time.time()})
                # Capturing only this environment prevents Pueue storing agent secrets.
                result = subprocess.run(
                    [
                        cfg["pueue"],
                        "-c",
                        cfg["pueueConfig"],
                        "add",
                        "--print-task-id",
                        "--escape",
                        "--group",
                        args.profile,
                        "--label",
                        f"wj:{recipe['id']}",
                        "--working-directory",
                        str(directory),
                        "--",
                        recipe["python"],
                        recipe["executor"],
                        "--config",
                        str(config_path),
                        "_execute",
                        str(directory),
                    ],
                    env=recipe["environment"],
                    check=True,
                    capture_output=True,
                    text=True,
                )
                task_id = result.stdout.strip()
                if not task_id.isdigit():
                    _fail(
                        "Unexpected acknowledgment; inspect native state before retry"
                    )
                receipt = {"taskId": task_id, "submitted": time.time()}
            _save(receipt_path, receipt)
        sys.stdout.write(recipe["id"] + "\n")


def _available() -> int:
    if platform.system() == "Linux":
        fields = dict(
            line.split(":", 1)
            for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines()
        )
        return int(fields["MemAvailable"].split()[0]) * 1024
    pressure = subprocess.check_output(
        ["/usr/sbin/sysctl", "-n", "kern.memorystatus_vm_pressure_level"],
        text=True,
        timeout=2,
    )
    if pressure.strip() != "1":
        return 0
    text = subprocess.check_output(["/usr/bin/vm_stat"], text=True, timeout=2)
    return _vm_available(text)


def _vm_available(text: str) -> int:
    """Interpret native page counters without treating compressed pages as free.

    Returns:
        Conservative available bytes, or zero for an unknown format.

    """
    page_size = re.search(r"page size of (\d+) bytes", text)
    if page_size is None:
        return 0
    size = int(page_size[1])
    # Conservative estimate; no compressed or wired pages counted as available.
    counts = dict(re.findall(r"^(Pages [^:]+):\s+(\d+)\.", text, re.MULTILINE))
    return (
        sum(
            int(counts.get(key, 0))
            for key in ("Pages free", "Pages inactive", "Pages speculative")
        )
        * size
    )


def _group_exists(pgid: int) -> bool:
    """Observe an owned positive process group without relying on its RSS.

    Returns:
        Whether a group still exists; denied observation remains an error.

    """
    if pgid <= 1:
        _fail("Native sampler requires an owned positive process group")
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    return True


async def _group_usage(
    pgid: int, cancelled: asyncio.Event, sample_seconds: float, *, ps: str = "/bin/ps"
) -> int:
    """Sample one owned group without blocking cancellation or querying other RSS.

    Returns:
        Sampled group RSS in bytes; group absence is checked independently.

    """
    if pgid <= 1:
        _fail("Native sampler requires an owned positive process group")
    # Darwin -g selects process groups. Linux fixtures retain the portable full
    # snapshot because procps -g selects sessions instead; filter exact PGIDs.
    selection = ["-g", str(pgid)] if platform.system() == "Darwin" else ["-A"]
    text = await _memory_sample(
        [ps, *selection, "-o", "pid=,pgid=,rss="],
        cancelled,
        sample_seconds,
        allow_empty_selection=True,
    )
    seen = set()
    usage = 0
    observed = False
    for line in text.splitlines():
        pid, group, rss = map(int, line.split())
        if pid <= 0 or group < 0 or rss < 0 or pid in seen:
            _fail("Invalid native RSS observation")
        seen.add(pid)
        if group == pgid:
            observed = True
            usage += rss * 1024
    if not observed:
        if _group_exists(pgid):
            _fail("Empty RSS observation for a live process group")
        return 0
    return usage


def _owner_unit(cfg: Json) -> str:
    unit = cfg.get("ownerUnit", "workstation-jobs.service")
    if not re.fullmatch(r"workstation-jobs(?:-audit-[0-9a-f]{32})?\.service", unit):
        _fail("Unsupported native queue owner")
    return unit


def _collect_resources(directory: Path) -> None:
    """Capture generic Linux service counters before its cgroup is removed."""
    recipe = _read(directory / "recipe.json")
    group = (
        Path("/proc/self/cgroup").read_text(encoding="utf-8").split("::", 1)[1].strip()
    )
    if not group.endswith("/workstation-job-" + recipe["id"] + ".service"):
        _fail("Resource finalizer must run inside its own job unit")
    root = Path("/sys/fs/cgroup") / group.lstrip("/")
    native = {
        "measurement": "kernel-at-unit-stop",
        "controlGroup": group,
        "MemoryPeak": _optional_counter(root / "memory.peak"),
        "MemorySwapPeak": _optional_counter(root / "memory.swap.peak"),
        "memoryEvents": {
            key: int(value)
            for key, value in (
                line.split()
                for line in (root / "memory.events")
                .read_text(encoding="utf-8")
                .splitlines()
            )
        },
        "memoryPressure": _optional_text(root / "memory.pressure"),
        "scopeResult": os.environ.get("SERVICE_RESULT"),
    }
    _save(directory / "native-resources.json", {"nativeResources": native})


def _optional_text(path: Path) -> str | None:
    """Keep unavailable optional kernel telemetry explicitly unknown.

    Returns:
        Observed text, or None when the kernel does not expose it.

    """
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return None


def _optional_counter(path: Path) -> int | None:
    """Read optional native counters without affecting mandatory stop proof.

    Returns:
        The counter value, or unknown when unavailable or unusable.

    """
    value = _optional_text(path)
    return int(value.strip()) if value is not None and value.strip().isdigit() else None


def _host_memory_pressure() -> str | None:
    """Observe optional Linux PSI without making telemetry an admission gate.

    Returns:
        Available pressure evidence, or None on kernels without PSI.

    """
    if platform.system() != "Linux":
        return "normal-at-sample"
    return _optional_text(Path("/proc/pressure/memory"))


def _file_sha256(path: Path) -> str:
    """Bind recovery observations to their unchanged durable input bytes.

    Returns:
        The SHA-256 digest of the complete file.

    """
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _darwin_id_absent(identifier: int, *, group: bool) -> bool:
    """Observe one kernel identity without signalling it.

    Returns:
        True only for ESRCH; permission or other probe failures refuse recovery.

    """
    probe = os.killpg if group else os.kill
    try:
        probe(identifier, 0)
    except ProcessLookupError:
        return True
    except OSError as error:
        _fail("Darwin process absence is unproven: " + type(error).__name__)
    return False


def _darwin_absent_processes(receipt: Json) -> None:
    """Require absent workers and their known post-spawn process group.

    Signal zero observes existence; EPERM or a reused live ID is uncertainty,
    never absence. No process is signalled or stopped during reconciliation.

    """
    for key in ("wrapperPid", "pid"):
        pid = receipt.get(key)
        if type(pid) is not int or not 1 < pid < 2**31:
            _fail("Darwin recovery requires well-formed recorded worker PIDs")
        if not _darwin_id_absent(pid, group=False):
            _fail("Recorded or reused worker PID still exists; preserve it")
    if not _darwin_id_absent(receipt["pid"], group=True):
        _fail("Recorded or reused payload process group still exists; preserve it")


def _reconcile_darwin(
    cfg: Json,
    directory: Path,
    task_id: str,
    task: Json,
    reviewed_executor: str | None,
) -> None:
    """Certify one reviewed, known post-spawn group without replay or restart."""
    if platform.system() != "Darwin":
        _fail("Darwin recovery requires native Darwin observations")
    if not reviewed_executor or not re.fullmatch(r"[0-9a-f]{64}", reviewed_executor):
        _fail(
            "Review the Darwin executor's owned-session contract and pass its SHA-256"
        )
    paths = {
        name: directory / name
        for name in ("execution.claim", "recipe.json", "result.json", "submission.json")
    }
    bindings = {name: _file_sha256(path) for name, path in paths.items()}
    recipe = _read(paths["recipe.json"])
    receipt = _read(paths["result.json"])
    claim = _read(paths["execution.claim"])
    executor = Path(recipe["executor"])
    if _file_sha256(executor) != reviewed_executor:
        _fail("Reviewed Darwin executor identity changed")
    if not all((
        recipe.get("id") == directory.name,
        recipe["config"]["profiles"][recipe["profile"]].get("backend") == "darwin",
        receipt.get("backend") == "darwin",
        receipt.get("lifecycleVersion") == LIFECYCLE_VERSION,
        claim.get("lifecycleVersion") == LIFECYCLE_VERSION,
        claim.get("pid") == receipt.get("wrapperPid"),
        receipt.get("pid") != receipt.get("wrapperPid"),
        isinstance(receipt.get("processIdentity"), str)
        and bool(receipt["processIdentity"].strip()),
        isinstance(receipt.get("wrapperIdentity"), str)
        and bool(receipt["wrapperIdentity"].strip()),
        receipt.get("phase")
        in {
            "executing",
            "supervision-error",
            "timeout",
            "cancelled",
            "failed",
            "memory-limit-observed",
            "host-memory-headroom-lost",
            "unresolved-descendants",
            "unproven-native-drain",
            "cleanup-error",
        },
    )):
        _fail("Darwin recovery requires a matching durable known post-spawn claim")
    terminal = _terminal(task)
    if terminal is None or terminal["result"] == "Success":
        _fail("Darwin reconciliation preserves an interrupted native failure")
    _darwin_absent_processes(receipt)
    # The state lock excludes adapter writes; native Pueue state is independently
    # observed twice. Recheck exact identities and bytes before publishing proof.
    after = _snapshot(cfg)["tasks"].get(task_id)
    _validate_native_identity(after, directory.name)
    if _terminal(after) != terminal:
        _fail("Native terminal state changed during Darwin recovery")
    _darwin_absent_processes(receipt)
    if (
        bindings != {name: _file_sha256(path) for name, path in paths.items()}
        or _file_sha256(executor) != reviewed_executor
    ):
        _fail("Darwin recovery input identity changed during observation")
    observation = {
        "measurement": "observed-absent-owned-process-group",
        "processGroup": receipt["pid"],
        "payloadStartIdentity": receipt["processIdentity"],
        "wrapperPid": receipt["wrapperPid"],
        "wrapperStartIdentity": receipt["wrapperIdentity"],
        "observations": 2,
        "probe": "signal-zero-ESRCH",
        "outputEOF": None,
        "observedGroupPeakBytes": None,
        "enforcement": "best-effort-process-group-excludes-detached-and-nix-daemon",
    }
    _save(directory / "native-resources.json", {"nativeResources": observation})
    proof = {
        "id": directory.name,
        "backend": "darwin",
        "drained": True,
        "at": time.time(),
        "taskId": task_id,
        "claimSha256": bindings["execution.claim"],
        "receiptSha256": bindings["result.json"],
        "recipeSha256": bindings["recipe.json"],
        "submissionSha256": bindings["submission.json"],
        "executorSha256": reviewed_executor,
        "resourcesSha256": _file_sha256(directory / "native-resources.json"),
        "nativeResultPreserved": terminal["result"],
        "nativeTerminal": terminal,
    }
    _save(directory / "reconciliation.json", proof)
    sys.stdout.write(json.dumps(proof) + "\n")


def _drain_proof_valid(directory: Path) -> bool:
    proof_path = directory / "reconciliation.json"
    native_path = directory / "native-resources.json"
    if not proof_path.exists() or not native_path.exists():
        return False
    proof = _read(proof_path)
    native = _read(native_path).get("nativeResources", {})
    group = native.get("controlGroup", "")
    if proof.get("backend") == "darwin":
        recipe = _read(directory / "recipe.json")
        # Validate the captured lifetime, not future unrelated numeric PID reuse.
        return bool(
            platform.system() == "Darwin"
            and proof.get("id") == directory.name
            and proof.get("drained") is True
            and native.get("measurement") == "observed-absent-owned-process-group"
            and recipe["config"]["profiles"][recipe["profile"]].get("backend")
            == "darwin"
            and proof.get("claimSha256") == _file_sha256(directory / "execution.claim")
            and proof.get("receiptSha256") == _file_sha256(directory / "result.json")
            and proof.get("recipeSha256") == _file_sha256(directory / "recipe.json")
            and proof.get("submissionSha256")
            == _file_sha256(directory / "submission.json")
            and proof.get("executorSha256") == _file_sha256(Path(recipe["executor"]))
            and proof.get("resourcesSha256") == _file_sha256(native_path)
        )
    return bool(
        proof.get("id") == directory.name
        and proof.get("drained") is True
        and proof.get("claimSha256")
        == hashlib.sha256((directory / "execution.claim").read_bytes()).hexdigest()
        and proof.get("resourcesSha256")
        == hashlib.sha256(native_path.read_bytes()).hexdigest()
        and native.get("measurement")
        in {"kernel-at-unit-stop", "manager-confirmed-absent"}
        and group.endswith("/workstation-job-" + directory.name + ".service")
        and not (Path("/sys/fs/cgroup") / group.lstrip("/")).exists()
    )


def _reconcile(
    cfg: Json,
    identifier: str,
    *,
    drain_idle_controller: bool = False,
    reviewed_darwin_executor: str | None = None,
) -> None:
    """Dispatch explicit recovery to its owning native evidence boundary."""
    directory = _job_path(_paths(cfg), identifier)
    recipe = _read(directory / "recipe.json")
    if recipe["config"]["profiles"][recipe["profile"]].get("backend") != "darwin":
        _reconcile_linux(cfg, identifier, drain_idle_controller=drain_idle_controller)
        return
    task_id = str(_read(directory / "submission.json")["taskId"])
    task = _snapshot(cfg)["tasks"].get(task_id)
    _validate_native_identity(task, identifier)
    if not _terminal(task):
        _fail("Only a terminal interrupted job can be reconciled")
    _reconcile_darwin(cfg, directory, task_id, task, reviewed_darwin_executor)


def _reconcile_linux(  # ruff: ignore[too-many-locals, complex-structure] - one explicit recovery transaction
    cfg: Json,
    identifier: str,
    *,
    drain_idle_controller: bool = False,
) -> None:
    """Accept native stop evidence while retaining the interrupted failure."""
    directory = _job_path(_paths(cfg), identifier)
    task_id = str(_read(directory / "submission.json")["taskId"])
    state = _snapshot(cfg)
    task = state["tasks"].get(task_id)
    _validate_native_identity(task, identifier)
    terminal = _terminal(task)
    if not terminal:
        _fail("Only a terminal interrupted job can be reconciled")
    receipt_path = directory / "result.json"
    receipt = _read(receipt_path) if receipt_path.exists() else {}
    for pid_key, identity_key in (
        ("pid", "processIdentity"),
        ("wrapperPid", "wrapperIdentity"),
    ):
        if (
            receipt.get(pid_key)
            and receipt.get(identity_key)
            and _process_identity(receipt[pid_key], cfg) == receipt[identity_key]
        ):
            _fail("Recorded worker still exists; preserve it for its owner")
    path = directory / "native-resources.json"
    if not path.exists():
        recipe = _read(directory / "recipe.json")
        if (
            recipe["config"]["profiles"][recipe["profile"]]["backend"] != "systemd"
            or receipt.get("phase") != "preflight"
            or receipt.get("pid")
            or not receipt.get("wrapperIdentity")
            or not drain_idle_controller
        ):
            _fail(
                "No native stop evidence; owner must investigate the unrecorded spawn"
            )
        # Preflight alone cannot exclude fork-before-exec. Drain the idle
        # controller's entire cgroup before accepting an absent payload unit.
        if any(not _terminal(value) for value in state["tasks"].values()):
            _fail("Controller has unfinished work; preserve it for its owners")
        controller_group = subprocess.check_output(
            [
                cfg["systemctl"],
                "--user",
                "show",
                _owner_unit(cfg),
                "--property=ControlGroup",
                "--value",
            ],
            text=True,
            timeout=2,
        ).strip()
        if not controller_group.startswith("/"):
            _fail("Controller cgroup is unavailable")
        subprocess.run(
            [cfg["systemctl"], "--user", "stop", _owner_unit(cfg)],
            check=True,
            timeout=15,
        )
        if (Path("/sys/fs/cgroup") / controller_group.lstrip("/")).exists():
            _fail("Controller cgroup has not drained")
        unit = "workstation-job-" + identifier + ".service"
        query = [
            cfg["systemctl"],
            "--user",
            "show",
            unit,
            "--property=LoadState",
            "--property=ActiveState",
        ]
        before = subprocess.check_output(query, text=True, timeout=2)
        processes = subprocess.check_output(
            [cfg["ps"], "-ww", "-axo", "args="], text=True, timeout=2
        )
        after = subprocess.check_output(query, text=True, timeout=2)
        if (
            "LoadState=not-found" not in before
            or "ActiveState=inactive" not in before
            or after != before
            or any(
                unit in line and "systemd-run" in line
                for line in processes.splitlines()
            )
        ):
            _fail(
                "Native preflight quiescence is not proven; preserve it for its owner"
            )
        subprocess.run(
            [
                cfg["systemctl"],
                "--user",
                "start",
                cfg.get("workloadSlice", "workstation-jobs-workload.slice"),
            ],
            check=True,
            timeout=15,
        )
        parent = subprocess.check_output(
            [
                cfg["systemctl"],
                "--user",
                "show",
                cfg.get("workloadSlice", "workstation-jobs-workload.slice"),
                "--property=ControlGroup",
                "--value",
            ],
            text=True,
            timeout=2,
        ).strip()
        if not parent.startswith("/"):
            _fail("Native workload parent is unavailable")
        group = parent + "/" + unit
        if (Path("/sys/fs/cgroup") / group.lstrip("/")).exists():
            _fail("Native preflight cgroup still exists")
        _save(
            path,
            {
                "nativeResources": {
                    "measurement": "manager-confirmed-absent",
                    "controlGroup": group,
                    "MemoryPeak": None,
                    "MemorySwapPeak": None,
                    "memoryEvents": None,
                    "memoryPressure": None,
                    "scopeResult": None,
                }
            },
        )
    native = _read(path).get("nativeResources", {})
    group = native.get("controlGroup", "")
    if (
        native.get("measurement")
        not in {"kernel-at-unit-stop", "manager-confirmed-absent"}
        or not group.endswith("/workstation-job-" + identifier + ".service")
        or (Path("/sys/fs/cgroup") / group.lstrip("/")).exists()
    ):
        _fail("Native unit stop and absent cgroup are not proven")
    proof = {
        "id": identifier,
        "drained": True,
        "at": time.time(),
        "claimSha256": hashlib.sha256(
            (directory / "execution.claim").read_bytes()
        ).hexdigest(),
        "resourcesSha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "nativeResultPreserved": terminal["result"],
    }
    _save(directory / "reconciliation.json", proof)
    sys.stdout.write(json.dumps(proof) + "\n")


def _execution_environment(recipe: Json, directory: Path) -> dict[str, str]:
    """Apply host compiler defaults while respecting explicitly retained values.

    Returns:
        The payload environment, including its owned job identity.

    """
    cfg = recipe["config"]
    environment = recipe["environment"].copy()
    environment["PATH"] = cfg["path"] + ":" + environment.get("PATH", "")
    if cfg["compilerCores"] > 0:
        environment.setdefault("CMAKE_BUILD_PARALLEL_LEVEL", str(cfg["compilerCores"]))
        environment.setdefault("CARGO_BUILD_JOBS", str(cfg["compilerCores"]))
        environment.setdefault("NIX_BUILD_CORES", str(cfg["compilerCores"]))
    environment["WORKSTATION_JOB_ID"] = recipe["id"]
    environment["WORKSTATION_JOB_DIRECTORY"] = str(directory)
    # Configure new Nix requests independently of scheduler slot count. Explicit
    # command flags and opted-in NIX_CONFIG values remain authoritative.
    defaults = cfg.get("nixSettings", {"max-jobs": 1, "cores": cfg["compilerCores"]})
    nix_config = environment.get("NIX_CONFIG", "")
    for name, value in defaults.items():
        if re.search(rf"(?m)^\s*{re.escape(name)}\s*=", nix_config) is None:
            nix_config += f"\n{name} = {value}\n"
    environment["NIX_CONFIG"] = nix_config
    return environment


async def _memory_sample(
    command: list[str],
    cancelled: asyncio.Event,
    sample_seconds: float,
    *,
    allow_empty_selection: bool = False,
) -> str:
    """Capture a fixed native sampler while cancellation and deadlines stay active.

    Returns:
        The completed sampler's text.

    Raises:
        TimeoutError: Sampling expired or its owner was cancelled.

    """
    process = await asyncio.create_subprocess_exec(
        *command,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
        start_new_session=True,
    )
    output = asyncio.create_task(process.communicate())
    cancellation = asyncio.create_task(cancelled.wait())
    try:
        done, _ = await asyncio.wait(
            {output, cancellation},
            timeout=max(0.001, sample_seconds),
            return_when=asyncio.FIRST_COMPLETED,
        )
        if cancelled.is_set() or output not in done:
            raise TimeoutError
        data, _ = output.result()
        if process.returncode and not (
            allow_empty_selection and process.returncode == 1 and not data.strip()
        ):
            _fail("Native memory sampling failed")
        return data.decode()
    finally:
        cancellation.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await cancellation
        if not output.done():
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGTERM)
            try:
                await asyncio.wait_for(asyncio.shield(output), timeout=0.2)
            except TimeoutError:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGKILL)
                await output


async def _darwin_available(cancelled: asyncio.Event, sample_seconds: float) -> int:
    """Read normal-pressure native capacity within one bounded sampling interval.

    Returns:
        Conservative available bytes, or zero under pressure.

    """
    deadline = time.monotonic() + max(0.001, sample_seconds)
    pressure = await _memory_sample(
        ["/usr/sbin/sysctl", "-n", "kern.memorystatus_vm_pressure_level"],
        cancelled,
        deadline - time.monotonic(),
    )
    if pressure.strip() != "1":
        return 0
    text = await _memory_sample(
        ["/usr/bin/vm_stat"], cancelled, deadline - time.monotonic()
    )
    return _vm_available(text)


async def _admit_native(
    recipe: Json, directory: Path, cancelled: asyncio.Event, started: float
) -> int | None:
    """Wait before payload launch and drain the owned helper on cancellation.

    Returns:
        The selected MiB grant, or None when no payload may launch.

    """
    cfg = recipe["config"]
    profile = cfg["profiles"][recipe["profile"]]
    bounds = recipe.get(
        "memoryRange",
        {"minimumMiB": recipe["memoryMiB"], "maximumMiB": recipe["memoryMiB"]},
    )
    allocation = directory / "memory-allocation.json"
    if profile["backend"] == "systemd":
        # The aggregate slice may be inactive before the first job. Start only
        # our declared slice so ControlGroup is meaningful before admission.
        await asyncio.to_thread(
            subprocess.run,
            [
                cfg["systemctl"],
                "--user",
                "start",
                cfg.get("workloadSlice", "workstation-jobs-workload.slice"),
            ],
            check=True,
            timeout=3,
        )
        group = (
            await asyncio.to_thread(
                subprocess.check_output,
                [
                    cfg["systemctl"],
                    "--user",
                    "show",
                    cfg.get("workloadSlice", "workstation-jobs-workload.slice"),
                    "-p",
                    "ControlGroup",
                    "--value",
                ],
                text=True,
                timeout=3,
            )
        ).strip()
        group = str(group)
        if not group.startswith("/") or ".." in Path(group).parts:
            _fail("Cannot establish the worker aggregate cgroup")
        process = await asyncio.create_subprocess_exec(
            cfg["memoryController"],
            "admit",
            "--receipt",
            str(allocation),
            "--minimum",
            str(bounds["minimumMiB"]),
            "--maximum",
            str(bounds["maximumMiB"]),
            "--reserve",
            str(cfg["reserveMiB"]),
            "--group",
            "/sys/fs/cgroup" + group,
            "--timeout",
            str(max(0.001, recipe["timeout"] - (time.monotonic() - started))),
            "--healthy-seconds",
            str(cfg.get("admissionHealthySeconds", 1)),
            "--pressure-limit",
            str(cfg.get("admissionPressureLimit", 50)),
            stdout=asyncio.subprocess.DEVNULL,
        )
        waiter = asyncio.create_task(process.wait())
        cancellation = asyncio.create_task(cancelled.wait())
        try:
            await asyncio.wait(
                {waiter, cancellation}, return_when=asyncio.FIRST_COMPLETED
            )
        finally:
            if process.returncode is None:
                process.terminate()
            await waiter
            cancellation.cancel()
        if not cancelled.is_set() and process.returncode not in {0, 124}:
            _fail("Native memory admission controller failed")
        if (
            cancelled.is_set()
            or process.returncode != 0
            or time.monotonic() - started >= recipe["timeout"]
        ):
            return None
        return _read(allocation)["grantMiB"]
    # Native macOS has no aggregate cgroup ceiling. Its pressure-aware capacity
    # sample and later process-group watchdog remain explicitly best effort.
    delay = 0.25
    healthy = None
    while not cancelled.is_set():
        now = time.monotonic()
        if now - started >= recipe["timeout"]:
            return None
        try:
            available = await _darwin_available(
                cancelled, min(2, recipe["timeout"] - (now - started))
            )
        except OSError, ValueError, subprocess.SubprocessError, TimeoutError:
            available = 0
        selected = min(
            bounds["maximumMiB"], max(0, available // MIB - cfg["reserveMiB"])
        )
        viable = selected >= bounds["minimumMiB"]
        healthy = (healthy if healthy is not None else now) if viable else None
        ready = healthy is not None and now - healthy >= cfg.get(
            "admissionHealthySeconds", 1
        )
        _save(
            allocation,
            {
                "phase": "admitted" if ready else "waiting-capacity",
                **bounds,
                "grantMiB": selected if ready else None,
                "availableBytes": available,
                "changes": [],
            },
        )
        if (
            ready
            and not cancelled.is_set()
            and time.monotonic() - started < recipe["timeout"]
        ):
            return selected
        with contextlib.suppress(TimeoutError):
            await asyncio.wait_for(
                cancelled.wait(), min(delay, recipe["timeout"] - (now - started))
            )
        delay = min(5, delay * 2)
    return None


async def _grow_darwin(  # ruff: ignore[too-many-arguments, too-many-positional-arguments] - explicit watchdog ownership and state
    recipe: Json,
    directory: Path,
    memory: int,
    usage: int,
    healthy: float | None,
    cancelled: asyncio.Event,
    sample_seconds: float,
) -> tuple[int, float | None]:
    """Adjust only the best-effort native watchdog allowance.

    Returns:
        The possibly enlarged byte allowance and healthy interval start.

    """
    cfg = recipe["config"]
    if "memoryRange" not in recipe or usage < memory * 4 // 5:
        return memory, None
    try:
        room = (
            await _darwin_available(cancelled, min(2, sample_seconds))
            - cfg["reserveMiB"] * MIB
            - max(0, memory - usage)
        )
    except OSError, ValueError, subprocess.SubprocessError, TimeoutError:
        room = 0
    increment = min(
        cfg.get("growthStepMiB", 256) * MIB,
        room,
        recipe["memoryRange"]["maximumMiB"] * MIB - memory,
    )
    now = time.monotonic()
    healthy = (healthy if healthy is not None else now) if increment >= MIB else None
    if healthy is not None and now - healthy >= cfg.get("growthHealthySeconds", 5):
        allocation = _read(directory / "memory-allocation.json")
        previous = memory // MIB
        memory += increment // MIB * MIB
        allocation["grantMiB"] = memory // MIB
        allocation["changes"].append({
            "fromMiB": previous,
            "toMiB": memory // MIB,
            "time": time.time(),
        })
        _save(directory / "memory-allocation.json", allocation)
        healthy = None
    return memory, healthy


async def _supervise(recipe: Json, directory: Path) -> int:  # ruff: ignore[complex-structure, too-many-branches, too-many-statements, too-many-locals] - one owned lifecycle
    cfg = recipe["config"]
    profile = cfg["profiles"][recipe["profile"]]
    backend = profile["backend"]
    memory = recipe["memoryMiB"] * MIB
    started = time.monotonic()
    loop = asyncio.get_running_loop()
    cancelled = asyncio.Event()
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        loop.add_signal_handler(sig, cancelled.set)
    receipt = {
        "id": recipe["id"],
        "sourceReference": recipe["sourceReference"],
        "host": platform.node(),
        "started": time.time(),
        "phase": "preflight",
        "memoryMiB": recipe["memoryMiB"],
        "timeout": recipe["timeout"],
        "backend": backend,
        "drained": False,
        "wrapperPid": os.getpid(),
        "wrapperIdentity": _process_identity(os.getpid(), cfg),
        "lifecycleVersion": LIFECYCLE_VERSION,
        "memorySamplingSeconds": 2 if backend == "darwin" else None,
        "schedulerQueueWaitSeconds": max(
            0, time.time() - recipe.get("created", time.time())
        ),
    }
    receipt_path = directory / "result.json"
    _save(receipt_path, receipt)
    environment = _execution_environment(recipe, directory)
    command = recipe["command"]
    unit = "workstation-job-" + recipe["id"] + ".service"
    if backend == "desktop":
        options = ["--bounded-memory", str(recipe["memoryMiB"] // 1024)]
        if "memoryRange" in recipe:
            options = [
                "--memory-min-mib",
                str(recipe["memoryRange"]["minimumMiB"]),
                "--memory-max-mib",
                str(recipe["memoryRange"]["maximumMiB"]),
            ]
        if _mode(profile, recipe["profile"]) == "daemon":
            options = []
        elif _mode(profile, recipe["profile"]) == "feedback":
            options = ["--feedback"]
        elif recipe["memoryMiB"] % 1024:
            _fail("Desktop bounded budgets must be whole GiB")
        if _mode(profile, recipe["profile"]) == "host-bounded":
            options += ["--host-preserving"]
        if "memoryController" in cfg:
            options += ["--admission-timeout", str(recipe["timeout"])]
        environment["WORKSTATION_QUEUE_OWNER_UNIT"] = _owner_unit(cfg)
        command = [cfg["workstationTask"], *options, *command]
    else:
        if "memoryController" in cfg:
            receipt["phase"] = "waiting-capacity"
            _save(receipt_path, receipt)
            try:
                selected = await _admit_native(recipe, directory, cancelled, started)
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                receipt.update(
                    phase="admission-error",
                    payloadLaunched=False,
                    drained=True,
                    exitCode=1,
                    finished=time.time(),
                    admissionErrorType=type(error).__name__,
                )
                _save(receipt_path, receipt)
                return 1
            if selected is None:
                receipt.update(
                    phase="cancelled-before-launch"
                    if cancelled.is_set()
                    else "admission-expired",
                    payloadLaunched=False,
                    drained=True,
                    exitCode=130 if cancelled.is_set() else 124,
                    finished=time.time(),
                )
                _save(receipt_path, receipt)
                return receipt["exitCode"]
            memory = selected * MIB
            receipt["admissionWaitSeconds"] = time.monotonic() - started
        available = (
            _read(directory / "memory-allocation.json")
            .get("sample", {})
            .get("availableBytes")
            if "memoryController" in cfg and backend == "systemd"
            else _read(directory / "memory-allocation.json").get("availableBytes")
            if "memoryController" in cfg
            else _available()
        )
        receipt["admission"] = {
            "availableBytes": available,
            "requiredBytes": memory + cfg["reserveMiB"] * MIB,
            "hostMemoryPressure": _host_memory_pressure(),
        }
        if (
            "memoryController" not in cfg
            and available < memory + cfg["reserveMiB"] * MIB
        ):
            receipt.update(
                phase="capacity-blocked",
                exitCode=75,
                finished=time.time(),
                drained=True,
            )
            _save(receipt_path, receipt)
            return 75
        if backend == "systemd":
            # A shared Nix daemon is outside the unit. Native Linux workers
            # expose only a read-only store; private local stores remain possible.
            command = [
                cfg["bubblewrap"],
                "--die-with-parent",
                "--bind",
                "/",
                "/",
                "--dev-bind",
                "/dev",
                "/dev",
                "--ro-bind",
                "/nix/store",
                "/nix/store",
                "--ro-bind",
                "/nix/var/nix",
                "/nix/var/nix",
                "--tmpfs",
                "/nix/var/nix/daemon-socket",
                "--",
                *command,
            ]
            command = [
                cfg["systemdRun"],
                "--user",
                "--quiet",
                "--wait",
                "--pipe",
                "--collect",
                "--unit",
                unit,
                "--working-directory",
                recipe["cwd"],
                *[f"--setenv={key}={value}" for key, value in environment.items()],
                "--slice",
                cfg.get("workloadSlice", "workstation-jobs-workload.slice"),
                "-p",
                f"MemoryMax={memory}",
                "-p",
                f"MemoryHigh={memory * 3 // 4}",
                "-p",
                "MemorySwapMax=0",
                "-p",
                "TasksMax=256",
                "-p",
                "OOMPolicy=kill",
                "-p",
                f"RuntimeMaxSec={recipe['timeout']}",
                "-p",
                "TimeoutStopSec=5",
                "-p",
                "BindsTo=" + _owner_unit(cfg),
                "-p",
                "After=" + _owner_unit(cfg),
                "-p",
                "ExecStopPost=-"
                + shlex.join([
                    recipe["python"],
                    recipe["executor"],
                    "--config",
                    str(directory / "configuration-root"),
                    "_resources",
                    str(directory),
                ]),
                "--",
                *command,
            ]
        elif backend != "darwin":
            _fail("Unsupported execution backend")
    if "memoryController" in cfg and (
        cancelled.is_set() or time.monotonic() - started >= recipe["timeout"]
    ):
        receipt.update(
            phase="cancelled-before-launch"
            if cancelled.is_set()
            else "admission-expired",
            payloadLaunched=False,
            drained=True,
            exitCode=130 if cancelled.is_set() else 124,
            finished=time.time(),
        )
        _save(receipt_path, receipt)
        return receipt["exitCode"]
    read_fd, write_fd = os.pipe()
    output_reader = asyncio.StreamReader()
    loop = asyncio.get_running_loop()
    read_file = os.fdopen(read_fd, "rb", buffering=0)
    output_transport, _ = await loop.connect_read_pipe(
        lambda: asyncio.StreamReaderProtocol(output_reader), read_file
    )
    try:
        process = await asyncio.create_subprocess_exec(
            *command,
            cwd=recipe["cwd"],
            env=environment,
            start_new_session=True,
            stdin=asyncio.subprocess.DEVNULL,
            stdout=write_fd,
            stderr=asyncio.subprocess.STDOUT,
        )
    except BaseException:
        output_transport.close()
        raise
    finally:
        os.close(write_fd)
    output = asyncio.create_task(
        _output(output_reader, cfg.get("logLimitMiB", 16) * MIB)
    )
    loop = asyncio.get_running_loop()
    waiter = asyncio.create_task(process.wait())
    cancellation = asyncio.create_task(cancelled.wait())
    peak = 0
    sampling_timeouts = 0
    consecutive_sampling_timeouts = 0
    last_usage: int | None = None
    reason = None
    if "memoryController" not in cfg:
        started = time.monotonic()  # Legacy runtimes counted from payload supervision.
    growth = None
    growth_healthy = None
    cleanup_errors: set[str] = set()
    try:  # ruff: ignore[too-many-statements-in-try-clause] - all post-spawn failures must reach owned cleanup
        if (
            backend == "systemd"
            and "memoryRange" in recipe
            and memory < recipe["memoryRange"]["maximumMiB"] * MIB
        ):
            growth = await asyncio.create_subprocess_exec(
                cfg["memoryController"],
                "grow",
                "--receipt",
                str(directory / "memory-allocation.json"),
                "--reserve",
                str(cfg["reserveMiB"]),
                "--unit",
                unit,
                "--systemctl",
                cfg["systemctl"],
                "--high-percent",
                "75",
                "--pressure-limit",
                str(cfg.get("admissionPressureLimit", 50)),
                "--growth-seconds",
                str(cfg.get("growthHealthySeconds", 5)),
                "--step",
                str(cfg.get("growthStepMiB", 256)),
            )
        # Install supervision before any fallible post-spawn identity or disk I/O.
        # The Process object owns this unreaped PID even if accounting fails.
        receipt.update(
            phase="executing" if backend == "darwin" else "executor-wait",
            pid=process.pid,
        )
        receipt["processIdentity"] = _process_identity(process.pid, cfg)
        _save(receipt_path, receipt)
        while True:
            if cancelled.is_set():
                reason = "cancelled"
                break
            if time.monotonic() - started >= recipe["timeout"]:
                reason = "timeout"
                break
            if backend == "darwin":
                try:
                    usage = await _group_usage(
                        process.pid,
                        cancelled,
                        min(
                            1,
                            max(
                                0.001, recipe["timeout"] - (time.monotonic() - started)
                            ),
                        ),
                        ps=cfg["ps"],
                    )
                except TimeoutError:
                    sampling_timeouts += 1
                    consecutive_sampling_timeouts += 1
                    if consecutive_sampling_timeouts > 1:
                        raise
                    # One missed ps sample is not a zero-RSS or completion
                    # observation. Retry on the normal notification wait so
                    # cancellation and the absolute deadline remain active.
                else:
                    consecutive_sampling_timeouts = 0
                    last_usage = usage
                    peak = max(peak, usage)
                    memory, growth_healthy = await _grow_darwin(
                        recipe,
                        directory,
                        memory,
                        usage,
                        growth_healthy,
                        cancelled,
                        recipe["timeout"] - (time.monotonic() - started),
                    )
                    if usage > memory:
                        reason = "memory-limit-observed"
                        break
                    if waiter.done() and usage == 0 and output.done():
                        break
                    # Admission is a snapshot. Recheck host headroom while the
                    # owned client runs; its RSS excludes the shared Nix daemon.
                    available = await _darwin_available(
                        cancelled,
                        min(
                            1,
                            max(
                                0.001, recipe["timeout"] - (time.monotonic() - started)
                            ),
                        ),
                    )
                    reserve = cfg["reserveMiB"] * MIB
                    receipt["hostMemoryObservation"] = {
                        "availableBytes": available,
                        "reserveBytes": reserve,
                        "observedAt": time.time(),
                    }
                    if available < reserve:
                        reason = "host-memory-headroom-lost"
                        break
            elif waiter.done():
                break
            # macOS has no process-group RSS notification; bounded 2s sampling is
            # a best-effort watchdog, not a kernel allocation cap. Also bounds
            # deadline checks while native executors perform notification waits.
            await asyncio.wait(
                {waiter, cancellation} if not waiter.done() else {cancellation},
                timeout=min(
                    2, max(0.01, recipe["timeout"] - (time.monotonic() - started))
                ),
                return_when=asyncio.FIRST_COMPLETED,
            )
    except (
        OSError,
        ValueError,
        subprocess.SubprocessError,
        TimeoutError,
        asyncio.CancelledError,
    ) as error:
        reason = "supervision-error"
        receipt["supervisionErrorType"] = type(error).__name__
    finally:
        if growth is not None:
            try:
                if growth.returncode is None:
                    growth.terminate()
                await asyncio.wait_for(growth.wait(), timeout=6)
            except (OSError, TimeoutError) as error:
                cleanup_errors.add(type(error).__name__)

        def signal_group(sig: int) -> None:
            """Keep denied cleanup observable without abandoning finalization."""
            try:
                os.killpg(process.pid, sig)
            except ProcessLookupError:
                return
            except OSError as error:
                cleanup_errors.add(type(error).__name__)

        if reason:
            if backend == "systemd":
                try:
                    stopped = await asyncio.to_thread(
                        subprocess.run,
                        [cfg["systemctl"], "--user", "stop", unit],
                        check=False,
                        timeout=6,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                    receipt["nativeStopExitCode"] = stopped.returncode
                except (OSError, subprocess.SubprocessError) as error:
                    receipt["nativeStopErrorType"] = type(error).__name__
                    cleanup_errors.add(type(error).__name__)
            signal_group(signal.SIGTERM)
            try:
                await asyncio.wait_for(asyncio.shield(waiter), timeout=6)
            except TimeoutError:
                signal_group(signal.SIGKILL)
            if backend == "darwin":
                signal_group(signal.SIGKILL)
        try:
            code = await asyncio.wait_for(asyncio.shield(waiter), timeout=6)
        except TimeoutError:
            cleanup_errors.add("TimeoutError")
            reason = reason or "unresolved-descendants"
            code = 1
            waiter.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await waiter
        try:
            truncated = await asyncio.wait_for(output, timeout=5)
            output_drained = True
        except (TimeoutError, OSError, ValueError, asyncio.CancelledError) as error:
            truncated = True
            output_drained = False
            reason = reason or "unresolved-descendants"
            cleanup_errors.add(type(error).__name__)
        output_transport.close()
        cancellation.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await cancellation
    if cleanup_errors:
        reason = reason or "cleanup-error"
    # The desktop runner only returns after its owned scope drains. A 75 payload
    # exit remains a failure: do not automatically replay it as memory admission.
    receipt.update(
        phase=reason or ("succeeded" if code == 0 else "failed"),
        exitCode=code if not reason else 124 if reason == "timeout" else 1,
        finished=time.time(),
        workerDurationSeconds=time.monotonic() - started,
        drained=output_drained and not cleanup_errors,
        nativeCleanupErrorTypes=sorted(cleanup_errors),
        observedGroupPeakBytes=peak if backend == "darwin" else None,
        outputTruncated=truncated,
        enforcement="best-effort-process-group-excludes-nix-daemon"
        if backend == "darwin"
        else "cgroup-v2-client-with-separate-shared-daemon"
        if backend == "desktop" and _allows_daemon(profile, recipe["profile"])
        else "cgroup-v2",
    )
    if backend == "darwin":
        # Zero RSS and output EOF do not certify absence of every group member.
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            receipt["nativeGroupAbsent"] = True
        except OSError as error:
            receipt["nativeGroupAbsent"] = False
            receipt["drained"] = False
            receipt["nativeCleanupErrorTypes"] = sorted(
                cleanup_errors | {type(error).__name__}
            )
        else:
            receipt["nativeGroupAbsent"] = False
            receipt["drained"] = False
        if not receipt["drained"]:
            receipt.update(
                phase=reason or "unresolved-descendants",
                exitCode=receipt["exitCode"] or 1,
            )
        receipt.update(
            memorySamplingTimeouts=sampling_timeouts,
            memorySamplingConsecutiveTimeouts=consecutive_sampling_timeouts,
            lastObservedGroupBytes=last_usage,
        )
    receipt["sharedNixDaemon"] = {
        "allowed": _allows_daemon(profile, recipe["profile"]),
        "includedInObservedGroupPeak": False,
    }
    if backend != "desktop":
        admission_wait = receipt.get("admissionWaitSeconds", 0)
        receipt["queueWaitSeconds"] = (
            receipt["schedulerQueueWaitSeconds"] + admission_wait
        )
        receipt["executionDurationSeconds"] = max(
            0, receipt["workerDurationSeconds"] - admission_wait
        )
    native_path = directory / "native-resources.json"
    if backend != "darwin" and native_path.exists():
        native = _read(native_path)
        receipt["nativeResources"] = native.get("nativeResources")
        receipt["admission"] = native.get("admission", receipt.get("admission"))
        if "executionMilliseconds" in native:
            receipt["executionDurationSeconds"] = native["executionMilliseconds"] / 1000
        if "admitted" in native and "created" in recipe:
            receipt["queueWaitSeconds"] = max(
                0, native["admitted"]["unixNs"] / 1e9 - recipe["created"]
            )
        if (
            backend == "desktop"
            and "memoryController" in cfg
            and "admitted" not in native
        ):
            receipt["payloadLaunched"] = False
            if receipt["exitCode"] == ADMISSION_EXPIRED_EXIT:
                receipt["phase"] = "admission-expired"
            elif reason == "cancelled":
                receipt.update(phase="cancelled-before-launch", exitCode=CANCELLED_EXIT)
        counters = native.get("nativeResources", {})
        receipt["observedGroupPeakBytes"] = counters.get("MemoryPeak")
        if counters.get("scopeResult") == "oom-kill" and not reason:
            receipt.update(phase="oom-killed", exitCode=1)
    if backend == "systemd":
        counters = receipt.get("nativeResources") or {}
        group = counters.get("controlGroup", "")
        proven = False
        if counters.get("measurement") == "kernel-at-unit-stop" and group.endswith(
            "/workstation-job-" + recipe["id"] + ".service"
        ):
            path = Path("/sys/fs/cgroup") / group.lstrip("/")
            try:
                proven = (
                    "populated 0"
                    in (path / "cgroup.events").read_text(encoding="utf-8").splitlines()
                )
            except FileNotFoundError:
                proven = not path.exists()
            except OSError:
                proven = False
        receipt["drained"] = output_drained and proven and not cleanup_errors
        if not receipt["drained"]:
            receipt.update(
                phase=reason or "unproven-native-drain",
                exitCode=receipt["exitCode"] or 1,
            )
    allocation = directory / "memory-allocation.json"
    if allocation.exists():
        receipt["memoryAllocation"] = _read(allocation)
    _save(receipt_path, receipt)
    return receipt["exitCode"]


def _process_identity(pid: int, cfg: Json) -> str:
    try:
        return subprocess.check_output(
            [cfg["ps"], "-p", str(pid), "-o", "lstart="], text=True, timeout=2
        ).strip()
    except subprocess.CalledProcessError:
        return ""


async def _output(reader: asyncio.StreamReader, limit: int) -> bool:
    used = 0
    while data := await reader.read(65536):
        remaining = max(0, limit - used)
        if remaining:
            sys.stdout.buffer.write(data[:remaining])
            sys.stdout.buffer.flush()
        used += len(data)
    if used > limit:
        sys.stdout.write("\n[workstation-job: retained output limit reached]\n")
    return used > limit


async def _wait(cfg: Json, task_id: str, seconds: int) -> int:
    observer = await asyncio.create_subprocess_exec(
        cfg["pueue"], "-c", cfg["pueueConfig"], "wait", "--quiet", task_id
    )
    try:
        return await asyncio.wait_for(observer.wait(), timeout=seconds)
    except TimeoutError:
        sys.stderr.write("workstation-job: observer deadline; durable job preserved\n")
        return 124
    finally:
        if observer.returncode is None:
            observer.terminate()
            await observer.wait()


async def _serve(cfg: Json, config_path: str) -> int:
    root = _paths(cfg)
    with (root / "daemon.lock").open("a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        _root_store(cfg, root, sys.argv[0], "daemon-runtime-root")
        _root_store(cfg, root, config_path, "daemon-config-root")
        # Close the protocol-readiness window to new adapter submissions while
        # recovery examines claims; Pueue restores queued groups paused.
        with _locked(root):
            _save(
                root / "queue-health.json",
                {"needsReconciliation": True, "phase": "starting", "time": time.time()},
            )
        previous = None
        with contextlib.suppress(ValueError):
            if (root / "pueue/state.json").exists():
                previous = _read(root / "pueue/state.json")
        daemon = await asyncio.create_subprocess_exec(
            cfg["pueued"], "-c", cfg["pueueConfig"]
        )
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            loop.add_signal_handler(
                sig, lambda: daemon.terminate() if daemon.returncode is None else None
            )
        # Pueue has a request protocol but no readiness subscription. Only safe
        # status reads retry here, with positive backoff and one 10s deadline.
        deadline = time.monotonic() + 10
        try:
            while True:
                try:
                    _snapshot(cfg)
                    break
                except subprocess.CalledProcessError:
                    if daemon.returncode is not None or time.monotonic() >= deadline:
                        raise
                    await asyncio.sleep(0.2)
            _initialise(cfg)
            _recover_queued(cfg, previous)
            if notify := os.environ.get("NOTIFY_SOCKET"):
                with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as channel:
                    channel.connect(
                        "\0" + notify[1:] if notify.startswith("@") else notify
                    )
                    channel.sendall(b"READY=1")
            return await daemon.wait()
        finally:
            if daemon.returncode is None:
                daemon.terminate()
                await daemon.wait()


def _check_interrupted(cfg: Json) -> None:
    root = _paths(cfg)
    # A daemon crash can leave external groups on macOS. PID plus start identity
    # protects unrelated processes against PID reuse. Preserve ambiguous work.
    for directory in (root / "jobs").iterdir():
        claim_path = directory / "execution.claim"
        version = (
            _read(claim_path).get("lifecycleVersion", 1) if claim_path.exists() else 1
        )
        if version >= LIFECYCLE_VERSION and _drain_proof_valid(directory):
            continue
        if not (directory / "result.json").exists():
            if version >= LIFECYCLE_VERSION:
                _fail(
                    "Unresolved execution claim has no terminal receipt; owner reconciliation required"
                )
            continue
        receipt = _read(directory / "result.json")
        if receipt.get("drained"):
            continue
        if version >= LIFECYCLE_VERSION:
            _fail(
                "Unresolved execution claim is not proven drained; owner reconciliation required"
            )
        for pid_key, identity_key in [
            ("wrapperPid", "wrapperIdentity"),
            ("pid", "processIdentity"),
        ]:
            pid = receipt.get(pid_key)
            identity = receipt.get(identity_key)
            if pid and identity and _process_identity(pid, cfg) == identity:
                _fail(
                    "Interrupted execution is still present; owner reconciliation required"
                )
        if (
            platform.system() == "Darwin"
            and receipt.get("pid")
            and _group_exists(receipt["pid"])
        ):
            _fail(
                "Interrupted process group still contains descendants; owner reconciliation required"
            )


def _resume(cfg: Json) -> None:
    _check_interrupted(cfg)
    for name in cfg["profiles"]:
        _native(cfg, "start", "--group", name)
    _save(
        _paths(cfg) / "queue-health.json",
        {"needsReconciliation": False, "time": time.time()},
    )


def _claim_execution(directory: Path) -> None:
    try:
        descriptor = os.open(
            directory / "execution.claim", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600
        )
    except FileExistsError:
        _fail(
            "This immutable execution was already claimed; never replay it automatically"
        )
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        json.dump(
            {
                "pid": os.getpid(),
                "time": time.time(),
                "lifecycleVersion": LIFECYCLE_VERSION,
            },
            stream,
        )
        stream.flush()
        os.fsync(stream.fileno())
    descriptor = os.open(directory, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    if directory.parent.name == "jobs" and re.fullmatch(
        r"[0-9a-f]{32}", directory.name
    ):
        pending = directory.parent.parent / "pending-claims"
        pending.mkdir(mode=0o700, exist_ok=True)
        _save(pending / (directory.name + ".json"), {"id": directory.name})


def _check_pending_claims(cfg: Json) -> None:
    """Gate new clients/workers even while a legacy daemon remains running."""
    root = _paths(cfg)
    pending = root / "pending-claims"
    if not pending.exists():
        return
    entries = list(pending.glob("*.json"))
    if not entries:
        return
    state = _snapshot(cfg)
    for marker in entries:
        identifier = _read(marker)["id"]
        directory = _job_path(root, identifier)
        receipt_path = directory / "result.json"
        if (
            receipt_path.exists() and _read(receipt_path).get("drained") is True
        ) or _drain_proof_valid(directory):
            marker.unlink(missing_ok=True)
            continue
        submitted = directory / "submission.json"
        task_id = str(_read(submitted).get("taskId")) if submitted.exists() else ""
        task = state["tasks"].get(task_id)
        # Submission acknowledgment may race with a very fast native launch.
        if task is None:
            task = next(
                (
                    value
                    for value in state["tasks"].values()
                    if value.get("label") == "wj:" + identifier
                ),
                None,
            )
        if (
            not task
            or task.get("label") != "wj:" + identifier
            or not any(name in task.get("status", {}) for name in ("Running", "Paused"))
        ):
            _fail(
                "Unresolved claimed worker blocks new admission; inspect doctor and reconcile its owner"
            )


def _recover_queued(cfg: Json, previous: Json | None) -> None:  # ruff: ignore[complex-structure] - explicit recovery cases
    root = _paths(cfg)
    state = _snapshot(cfg)
    resumed = []
    blocked = []
    interrupted = previous is not None and any(
        any(kind in task.get("status", {}) for kind in ("Running", "Paused"))
        for task in previous.get("tasks", {}).values()
    )
    try:
        _check_interrupted(cfg)
    except ValueError:
        interrupted = True
    if interrupted:
        # Even a running-only crash (no queued successor) can leave an external
        # macOS worker. Pause admission without signaling that surviving work.
        for name in cfg["profiles"]:
            _native(cfg, "pause", "--group", name, "--wait")
    if previous and not (root / "maintenance.json").exists():
        for name in cfg["profiles"]:
            was_running = (
                previous.get("groups", {}).get(name, {}).get("status") == "Running"
            )
            queued = [
                task
                for task in state["tasks"].values()
                if task.get("group") == name and "Queued" in task.get("status", {})
            ]
            if (
                not was_running
                or not queued
                or state["groups"][name]["status"] != "Paused"
            ):
                continue
            try:  # ruff: ignore[too-many-statements-in-try-clause] - one group recovery transaction
                if interrupted:
                    _fail("Interrupted native execution requires reconciliation")
                _check_interrupted(cfg)
                for task in queued:
                    label = task.get("label") or ""
                    directory = _job_path(root, label.removeprefix("wj:"))
                    if (
                        not label.startswith("wj:")
                        or not (directory / "recipe.json").exists()
                        or (directory / "execution.claim").exists()
                    ):
                        _fail("Queued execution has ambiguous prior state")
                _native(cfg, "start", "--group", name)
                resumed.append(name)
            except ValueError:
                blocked.append(name)
    _save(
        root / "queue-health.json",
        {
            "needsReconciliation": bool(blocked) or bool(interrupted),
            "autoResumed": resumed,
            "blockedGroups": blocked,
            "time": time.time(),
        },
    )
    if blocked or interrupted:
        sys.stderr.write(
            "workstation-job: interrupted or ambiguous jobs require owner reconciliation; inspect doctor\n"
        )


def _validate_native_identity(task: Json | None, identifier: str) -> None:
    if task is None or task.get("label") != f"wj:{identifier}":
        _fail("Native ID no longer belongs to this request; reconciliation required")


def _activation_check(cfg: Json) -> None:
    root = _paths(cfg)
    with _locked(root):
        try:
            state = _snapshot(cfg)
        except subprocess.CalledProcessError:
            return  # Fresh installation; no daemon to replace.

        def completed(task: Json) -> bool:
            if _terminal(task):
                return True
            label = task.get("label") or ""
            status = task.get("status", {})
            if (
                not isinstance(status, dict)
                or "Stashed" not in status
                or not re.fullmatch(r"wj:[0-9a-f]{32}", label)
            ):
                return False
            directory = _job_path(root, label.removeprefix("wj:"))
            receipt = directory / "result.json"
            if not receipt.exists() or (directory / "execution.claim").exists():
                return False
            result = _read(receipt)
            return (
                result.get("id") == label.removeprefix("wj:")
                and result.get("phase") == "cancelled-before-start"
                and result.get("exitCode") == CANCELLED_EXIT
                and result.get("drained") is True
            )

        if any(not completed(task) for task in state["tasks"].values()):
            _fail(
                "Queue has unfinished jobs; finish or explicitly reconcile them before configuration activation"
            )
        _check_interrupted(cfg)
        if (root / "maintenance.json").exists():
            return  # Preserve original running/paused intent across failed activation.
        record = {"groups": state["groups"], "time": time.time()}
        _save(root / "maintenance.json", record)
        for name in state["groups"]:
            _native(cfg, "pause", "--group", name, "--wait")


def _activation_finish(cfg: Json) -> None:
    root = _paths(cfg)
    with _locked(root):
        path = root / "maintenance.json"
        if not path.exists():
            return
        record = _read(path)
        state = _snapshot(cfg)
        for name, group in record["groups"].items():
            if name in state["groups"] and group["status"] == "Running":
                _native(cfg, "start", "--group", name)
        path.unlink()


def _initialise(cfg: Json) -> None:
    _paths(cfg)
    state = _snapshot(cfg)
    for name in cfg["profiles"]:
        if name not in state["groups"]:
            _native(cfg, "group", "add", name)
        _native(cfg, "parallel", "--group", name, "1")
    _native(cfg, "pause", "--group", "default", "--wait")


def _reconciled_receipt(
    directory: Path, task: Json | None, receipt: Json | None
) -> Json:
    """Present a recovered failure without replacing its original receipt.

    Returns:
        The effective receipt and its separately preserved reconciliation proof.

    """
    if receipt is None or not _drain_proof_valid(directory):
        return {"receipt": receipt, "reconciliation": None}
    proof = _read(directory / "reconciliation.json")
    if proof.get("backend") == "darwin":
        if (_terminal(task) if task else None) != proof.get("nativeTerminal"):
            return {"receipt": receipt, "reconciliation": None}
        receipt |= {
            "phase": "interrupted",
            "exitCode": 1,
            "drained": True,
            "originalReceiptSha256": proof["receiptSha256"],
            "drainMeasurement": "observed-absent-owned-process-group",
            "outputEOF": None,
        }
    return {"receipt": receipt, "reconciliation": proof}


def _inspect(
    cfg: Json, identifier: str | None = None, *, history_limit: int = HISTORY_LIMIT
) -> None:
    state = _snapshot(cfg)
    root = _paths(cfg)
    result = {
        "host": platform.node(),
        "groups": state["groups"],
        "jobs": [],
        "maintenance": _read(root / "maintenance.json")
        if (root / "maintenance.json").exists()
        else None,
    }
    result["recovery"] = (
        _read(root / "queue-health.json")
        if (root / "queue-health.json").exists()
        else None
    )
    directories = (
        [_job_path(root, identifier)] if identifier else (root / "jobs").iterdir()
    )
    unfinished = []
    history = []
    for directory in directories:
        if not (directory / "recipe.json").exists():
            continue
        recipe = _read(directory / "recipe.json")
        submitted = (
            _read(directory / "submission.json")
            if (directory / "submission.json").exists()
            else {}
        )
        task = state["tasks"].get(str(submitted.get("taskId")))
        if task and task.get("label") != f"wj:{recipe['id']}":
            task = None
        receipt = (
            _read(directory / "result.json")
            if (directory / "result.json").exists()
            else None
        )
        executor_path = directory / "native-resources.json"
        executor = _read(executor_path) if executor_path.exists() else None
        record: Json = {
            "id": recipe["id"],
            "owner": recipe["owner"],
            "profile": recipe["profile"],
            "sourceReference": recipe["sourceReference"],
            "taskId": submitted.get("taskId"),
            "nativeStatus": task.get("status")
            if task
            else "missing-needs-reconciliation",
            "created": recipe.get("created", 0),
            **_reconciled_receipt(directory, task, receipt),
            "executor": executor,
            "memoryAllocation": _read(directory / "memory-allocation.json")
            if (directory / "memory-allocation.json").exists()
            else None,
        }
        receipt = record["receipt"]
        cancelled = (
            receipt is not None
            and receipt.get("phase") == "cancelled-before-start"
            and receipt.get("drained") is True
            and not (directory / "execution.claim").exists()
            and (task is None or "Stashed" in task.get("status", {}))
        )
        unresolved = (
            not receipt
            or receipt.get("drained") is not True
            or receipt.get("exitCode") is None
            or (task is not None and _terminal(task) is None and not cancelled)
            or (task is None and not cancelled)
        )
        (unfinished if unresolved else history).append(record)
    unfinished.sort(key=operator.itemgetter("created", "id"), reverse=True)
    history.sort(key=operator.itemgetter("created", "id"), reverse=True)
    result["jobs"] = unfinished + (history if identifier else history[:history_limit])
    result["historyTruncated"] = not identifier and len(history) > history_limit
    sys.stdout.write(json.dumps(result, sort_keys=True) + "\n")


def main() -> int:  # ruff: ignore[complex-structure, too-many-branches, too-many-statements, too-many-locals] - CLI dispatch
    """Dispatch the finite job interface.

    Returns:
        Zero only for a successful requested operation.

    """
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config",
        default=os.environ.get(
            "WORKSTATION_JOBS_CONFIG",
            str(Path.home() / ".config/workstation-jobs/config.json"),
        ),
    )
    commands = parser.add_subparsers(dest="action", required=True)
    add = commands.add_parser("submit")
    for name in ("owner", "key", "source"):
        add.add_argument("--" + name, required=True)
    add.add_argument("--cwd", default=str(Path.cwd()))
    add.add_argument(
        "--profile",
        help="auto uses declared memory/deadline, defaulting to bounded work",
    )
    add.add_argument(
        "--requires-daemon",
        action="store_true",
        help="explicitly require the shared Nix daemon and its bulk admission guard",
    )
    add.add_argument("--memory-mib", type=int)
    add.add_argument("--memory-min-mib", type=int)
    add.add_argument("--memory-max-mib", type=int)
    add.add_argument("--timeout", type=int)
    add.add_argument("--env", action="append", default=[])
    add.add_argument("command", nargs=argparse.REMAINDER)
    status = commands.add_parser("status")
    status.add_argument("id", nargs="?")
    for name in ("wait", "log", "cancel"):
        sub = commands.add_parser(name)
        sub.add_argument("id")
        if name == "wait":
            sub.add_argument("--timeout", type=int, default=1200)
    commands.add_parser("init")
    commands.add_parser("serve")
    doctor = commands.add_parser("doctor")
    doctor.add_argument(
        "--history-limit",
        type=int,
        default=HISTORY_LIMIT,
        help="maximum completed records; 0 keeps only active or unresolved jobs",
    )
    commands.add_parser("activation-check")
    commands.add_parser("activation-finish")
    recover = commands.add_parser("resume-queued")
    recover.add_argument(
        "--acknowledge-interrupted", action="store_true", required=True
    )
    reconcile = commands.add_parser("reconcile")
    reconcile.add_argument("id")
    reconcile.add_argument(
        "--acknowledge-interrupted", action="store_true", required=True
    )
    reconcile.add_argument("--drain-idle-controller", action="store_true")
    reconcile.add_argument(
        "--reviewed-darwin-executor",
        help="Reviewed SHA-256 of the Darwin executor's owned-session contract",
    )
    for name in ("_execute", "_resources"):
        execute = commands.add_parser(name)
        execute.add_argument("directory")
    args = parser.parse_args()
    if args.action == "doctor" and args.history_limit < 0:
        parser.error("history limit must be non-negative")
    cfg = _read(args.config)
    root = _paths(cfg)
    if args.action == "submit":
        _submit(cfg, str(Path(args.config).resolve()), args)
    elif args.action == "_execute":
        directory = Path(args.directory)
        _check_pending_claims(cfg)
        _claim_execution(directory)
        result = asyncio.run(_supervise(_read(directory / "recipe.json"), directory))
        if _read(directory / "result.json").get("drained") is True:
            (root / "pending-claims" / (directory.name + ".json")).unlink(
                missing_ok=True
            )
        return result
    elif args.action == "_resources":
        _collect_resources(Path(args.directory))
    elif args.action == "reconcile":
        try:
            with _locked(root):
                _reconcile(
                    cfg,
                    args.id,
                    drain_idle_controller=args.drain_idle_controller,
                    reviewed_darwin_executor=args.reviewed_darwin_executor,
                )
        finally:
            # Startup takes the same state lock; restart only after releasing it.
            if args.drain_idle_controller and platform.system() == "Linux":
                subprocess.run(
                    [cfg["systemctl"], "--user", "start", _owner_unit(cfg)],
                    check=True,
                    timeout=30,
                )
    elif args.action == "serve":
        return asyncio.run(_serve(cfg, args.config))
    elif args.action == "init":
        _initialise(cfg)
    elif args.action in {"status", "doctor"}:
        _inspect(
            cfg,
            getattr(args, "id", None),
            history_limit=getattr(args, "history_limit", HISTORY_LIMIT),
        )
    elif args.action == "activation-check":
        _activation_check(cfg)
    elif args.action == "activation-finish":
        _activation_finish(cfg)
    elif args.action == "resume-queued":
        # Native start --group preserves normal dependency/parallel scheduling.
        # Interrupted tasks remain Done(Killed); they are never restarted here.
        _resume(cfg)
        (root / "maintenance.json").unlink(missing_ok=True)
    else:
        directory = _job_path(root, args.id)
        task_id = str(_read(directory / "submission.json")["taskId"])
        task = _snapshot(cfg)["tasks"].get(task_id)
        _validate_native_identity(task, args.id)
        if args.action == "log":
            sys.stdout.write(_native(cfg, "log", task_id, "--lines", "100", "--json"))
        elif args.action == "cancel":
            task = _snapshot(cfg)["tasks"][task_id]
            if "Queued" in task["status"] or "Stashed" in task["status"]:
                _native(cfg, "stash", task_id, capture=False)
                _save(
                    directory / "result.json",
                    {
                        "id": args.id,
                        "phase": "cancelled-before-start",
                        "exitCode": 130,
                        "drained": True,
                    },
                )
            elif not _terminal(task):
                _native(cfg, "kill", "--signal", "SIGTERM", task_id, capture=False)
        else:
            # Pueue's native blocking wait uses notifications. Interruption of
            # this observer does not cancel the durable job.
            if (directory / "result.json").exists() and _read(
                directory / "result.json"
            ).get("phase") == "cancelled-before-start":
                return 130
            observed = asyncio.run(_wait(cfg, task_id, args.timeout))
            if observed:
                return observed
            task = _snapshot(cfg)["tasks"].get(task_id)
            _validate_native_identity(task, args.id)
            _inspect(cfg, args.id)
            terminal = _terminal(task)
            return 0 if terminal and terminal["result"] == "Success" else 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError, KeyError) as error:
        sys.stderr.write(f"workstation-job: {error}\n")
        sys.exit(1)
