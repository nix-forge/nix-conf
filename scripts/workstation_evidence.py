"""Record source-bound workstation checks and comparable command measurements.

Reports and command logs are private local evidence. A successful command records
only its stated phase; it never implies activation, recovery or hardware success.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import math
import os
import platform
import re
import shutil
import signal
import statistics
import subprocess
import sys
import threading
import time
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

SCHEMA = 1
MIN_TRIALS = 3
VERIFICATION_TIMEOUT = 120
ACTIVE_SYSTEM = Path("/run/current-system")
SYSTEM_PHASES = {"runtime", "recovery", "activation", "dry-activation"}
PHASES = (
    "evaluation",
    "build",
    "dry-activation",
    "activation",
    "runtime",
    "recovery",
    "vm",
)


def git(root: Path, *args: str) -> bytes:
    """Read Git state without caller index or worktree overrides.

    Returns:
        The Git command output.

    """
    env = {
        key: value for key, value in os.environ.items() if not key.startswith("GIT_")
    }
    return subprocess.check_output(
        ["git", "-C", str(root), *args], env=env, timeout=VERIFICATION_TIMEOUT
    )


def digest(value: bytes) -> str:
    """Hash bytes without exposing their contents.

    Returns:
        A hexadecimal SHA-256 digest.

    """
    return hashlib.sha256(value).hexdigest()


def repository_root(root: Path) -> Path:
    """Require a whole Git source instead of a partial nested-flake fingerprint.

    Returns:
        The resolved repository root.

    Raises:
        ValueError: The supplied source omits part of its owning Git repository.

    """
    root = root.resolve()
    toplevel = Path(
        os.fsdecode(git(root, "rev-parse", "--show-toplevel")).strip()
    ).resolve()
    if root != toplevel:
        raise ValueError(
            "Use the Git repository root as --source so all flake inputs are fingerprinted"
        )
    return root


def source_identity(root: Path) -> dict[str, Any]:
    """Fingerprint the exact tracked worktree, including dirty initialized submodules.

    Untracked files are excluded just as with a Git flake reference. Intent-to-add
    files are included. Missing tracked files, symlinks and executable mode changes
    contribute to identity. Unmerged or unavailable submodule state fails closed.

    Returns:
        Revision, worktree digest, lockfile digests and recursive submodule state.

    Raises:
        ValueError: Source has unresolved conflicts, unavailable submodules or unsupported files.

    """
    root = repository_root(root)
    entries = []
    submodules = {}
    locks = {}
    for record in git(root, "ls-files", "--stage", "-z").split(b"\0"):
        if not record:
            continue
        metadata, raw_name = record.split(b"\t", 1)
        mode, _oid, stage = metadata.decode().split()
        name = os.fsdecode(raw_name)
        path = root / name
        if stage != "0":
            raise ValueError("Resolve merge conflicts before recording source evidence")
        if mode == "160000":
            # Empty submodule directories otherwise make git search the parent.
            if not (path / ".git").exists():
                raise ValueError(f"Initialize the {name} submodule before validation")
            sub = source_identity(path)
            submodules[name] = sub
            entries.append([name, mode, sub["tree_sha256"]])
        elif path.is_symlink():
            entries.append([name, "120000", digest(os.fsencode(path.readlink()))])
        elif path.is_file():
            with path.open("rb") as stream:
                content_digest = hashlib.file_digest(stream, "sha256").hexdigest()
            actual_mode = "100755" if path.stat().st_mode & 0o111 else "100644"
            entries.append([name, actual_mode, content_digest])
            if path.name == "flake.lock":
                locks[name] = content_digest
        elif not path.exists():
            # Git flakes omit missing files, whether deletion is staged or not.
            continue
        else:
            raise ValueError(f"Unsupported tracked file kind: {name}")
    # Staged blob IDs describe the index, not the bytes consumed by the flake.
    entries.sort(key=lambda entry: os.fsencode(entry[0]))
    dirty = bool(
        git(
            root,
            "status",
            "--porcelain",
            "--untracked-files=no",
            "--ignore-submodules=untracked",
        )
    )
    return {
        "revision": git(root, "rev-parse", "HEAD").decode().strip(),
        "tree_sha256": digest(json.dumps(entries, ensure_ascii=True).encode()),
        "dirty": dirty,
        "lockfiles": locks,
        "submodules": submodules,
    }


def now() -> str:
    """Date a receipt.

    Returns:
        The current UTC ISO timestamp.

    """
    return datetime.now(UTC).isoformat()


def native_system() -> str:
    """Identify the execution platform.

    Returns:
        The architecture and OS using Nix platform spelling.

    """
    machine = {"arm64": "aarch64", "AMD64": "x86_64"}.get(
        platform.machine(), platform.machine()
    )
    return f"{machine}-{platform.system().lower()}"


def private_directory(path: Path, root: Path) -> Path:
    """Keep raw execution evidence outside the published configuration tree.

    Returns:
        The resolved private output directory.

    Raises:
        ValueError: The destination is public or inside the source repository.

    """
    path = path.expanduser().resolve()
    if path.is_relative_to(root.resolve()):
        raise ValueError("Evidence must be stored outside the repository")
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.stat().st_mode & 0o077:
        raise ValueError("Evidence directory must be private, with mode 0700")
    return path


def write_json(path: Path, value: object) -> None:
    """Atomically write a new private receipt without overwriting another run."""
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    try:
        with temporary.open("x", encoding="utf-8") as stream:
            temporary.chmod(0o600)
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def kill_group(pid: int) -> None:
    """Terminate only the child session created for this command."""
    with contextlib.suppress(ProcessLookupError):
        os.killpg(pid, signal.SIGKILL)


def reject_descendants(pid: int) -> bool:
    """Terminate asynchronous work left after the command leader exits.

    Returns:
        Whether descendants remained in the owned process group.

    """
    try:
        os.killpg(pid, 0)
    except ProcessLookupError:
        return False
    kill_group(pid)
    return True


def measure(
    command: list[str], root: Path, log: Path, timeout: float
) -> dict[str, Any]:
    """Measure a synchronous command and reject surviving background work.

    Peak RSS is the OS wait4 maximum, not aggregate process-tree memory.
    Nix daemon and remote builder resource usage is excluded. Ordinary children
    share the owned session; commands that escape it are outside this contract.

    Returns:
        Exit status, timeout flag, elapsed time and resource measurements.

    """
    started = time.monotonic()
    expired = threading.Event()
    with log.open("xb") as output:
        log.chmod(0o600)
        with subprocess.Popen(
            command,
            cwd=root,
            stdout=output,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        ) as process:

            def terminate() -> None:
                expired.set()
                kill_group(process.pid)

            timer = threading.Timer(timeout, terminate)
            timer.daemon = True
            timer.start()
            try:
                _, status, usage = os.wait4(process.pid, 0)
                process.returncode = os.waitstatus_to_exitcode(status)
                descendants = reject_descendants(process.pid)
            except BaseException:
                kill_group(process.pid)
                process.wait()
                raise
            finally:
                timer.cancel()
                timer.join()
    rss = usage.ru_maxrss / 1024 if platform.system() == "Darwin" else usage.ru_maxrss
    return {
        "exit_code": process.returncode,
        "timed_out": expired.is_set(),
        "descendants_remained": descendants,
        "elapsed_seconds": time.monotonic() - started,
        "peak_rss_kib": rss,
        "user_seconds": usage.ru_utime,
        "system_seconds": usage.ru_stime,
    }


def nix_output(root: Path, *args: str) -> str:
    """Run bounded candidate verification, cleaning up its owned child group.

    Returns:
        The verification command's standard output.

    Raises:
        ValueError: Verification left asynchronous descendants running.
        subprocess.CalledProcessError: Nix rejected the candidate.

    """
    command = ["nix", *args]
    with subprocess.Popen(
        command,
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
        text=True,
    ) as process:
        try:
            stdout, stderr = process.communicate(timeout=VERIFICATION_TIMEOUT)
        except BaseException:
            kill_group(process.pid)
            process.communicate()
            raise
        if reject_descendants(process.pid):
            raise ValueError("Candidate verification left background processes running")
        if process.returncode:
            raise subprocess.CalledProcessError(
                process.returncode, command, stdout, stderr
            )
    return stdout.strip()


def active_generation() -> str | None:
    """Observe the active system without substituting the candidate for missing state.

    Returns:
        The resolved live generation, or no observation if it is unavailable.

    """
    return str(ACTIVE_SYSTEM.resolve()) if ACTIVE_SYSTEM.exists() else None


def runtime_matches(system_path: str | None, active_path: Path) -> bool:
    """Compare the recorded output with the active generation.

    Returns:
        Whether both existing paths resolve to the same output.

    """
    return bool(
        system_path
        and active_path.exists()
        and Path(system_path).exists()
        and active_path.resolve() == Path(system_path).resolve()
    )


def build_candidate(args: argparse.Namespace) -> dict[str, Any]:
    """Evaluate the explicitly named candidate before measuring its build.

    Returns:
        The output attribute and evaluated store path, when requested.

    Raises:
        ValueError: Build options or the evaluated path are invalid.

    """
    if args.build_receipt:
        raise ValueError("A build cannot reuse another build receipt")
    if args.check == "full-system" and not args.installable:
        raise ValueError("Full-system builds require --installable")
    if not args.installable:
        return {}
    if not isinstance(args.installable, str) or not re.fullmatch(
        r"[A-Za-z0-9_.-]+", args.installable
    ):
        raise ValueError("Use a plain root output attribute for --installable")
    output = nix_output(
        args.source.resolve(),
        "eval",
        "--raw",
        f"{args.source.resolve()}#{args.installable}.outPath",
    )
    if not store_path(output):
        raise ValueError("Candidate evaluation did not return a Nix store output")
    return {"system_path": output, "installable": args.installable}


def candidate_path(args: argparse.Namespace, before: dict[str, Any]) -> dict[str, Any]:
    """Resolve a build output or reuse a complete matching native build receipt.

    Returns:
        Candidate output and the provenance needed by dependent phases.

    Raises:
        ValueError: The output attribute or prior evidence is incompatible.

    """
    if args.phase == "build":
        return build_candidate(args)
    if args.installable:
        raise ValueError("Use --installable only with a build")
    if args.phase not in SYSTEM_PHASES:
        if args.build_receipt:
            raise ValueError("Build receipts are only used by system validation phases")
        return {}
    if not args.build_receipt:
        raise ValueError("System validation requires matching candidate build evidence")
    built = read_receipt(args.build_receipt)
    if not (
        built["status"] == "passed"
        and built["phase"] == "build"
        and built["source"] == before
        and built["target"] == args.target
        and built["system"] == native_system()
        and built.get("installable")
    ):
        raise ValueError(
            "Build receipt must prove this source, target and native system"
        )
    return {
        "system_path": built["system_path"],
        "installable": built["installable"],
        "build_receipt_sha256": digest(args.build_receipt.read_bytes()),
    }


def run_trials(
    args: argparse.Namespace,
    command: list[str],
    output: Path,
    identifier: str,
    record: dict[str, Any],
) -> None:
    """Run repetitions until failure, preserving every completed observation."""
    root = args.source.resolve()
    for trial in range(args.runs):
        log = output / f"{identifier}-{trial + 1}.log"
        try:
            measured = measure(command, root, log, args.timeout)
        except OSError as error:
            record["reason"] = f"Could not start command: {error.strerror}"
            break
        measured["log"] = log.name
        record["measurements"].append(measured)
        if (
            measured["exit_code"] != 0
            or measured["timed_out"]
            or measured["descendants_remained"]
        ):
            break


def nix_configuration(root: Path) -> dict[str, str]:
    """Hash effective client settings without persisting their potentially private values.

    Returns:
        A canonical configuration digest or an explicit unavailable observation.

    """
    try:
        settings = json.loads(nix_output(root, "config", "show", "--json"))
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        return {"status": "unavailable", "reason": type(error).__name__}
    if not isinstance(settings, dict) or not settings:
        return {
            "status": "unavailable",
            "reason": "Empty or invalid effective configuration",
        }
    return {
        "status": "captured",
        "sha256": digest(json.dumps(settings, sort_keys=True).encode()),
    }


def verify_configuration_stability(record: dict[str, Any], root: Path) -> None:
    """Retain differing effective-configuration observations without inventing stability.

    Raises:
        ValueError: Settings changed or their two observations cannot be compared.

    """
    after = nix_configuration(root)
    if record["nix_configuration"] == after:
        return
    record["nix_configuration_after"] = after
    if (
        after["status"] != "captured"
        or record["nix_configuration"]["status"] != "captured"
    ):
        raise ValueError(
            "Effective Nix client configuration could not be compared across execution"
        )
    raise ValueError("Effective Nix client configuration changed during execution")


def new_record(args: argparse.Namespace, command: list[str]) -> dict[str, Any]:
    """Create the complete receipt envelope before attempting verification.

    Returns:
        An unsuccessful observation ready to collect execution evidence.

    """
    root = args.source.resolve()
    return {
        "schema": SCHEMA,
        "kind": "benchmark" if args.runs > 1 else "check",
        "date": now(),
        "target": args.target,
        "check": args.check,
        "phase": args.phase,
        "system": getattr(args, "system", None) or native_system(),
        "source": source_identity(root),
        "cache_condition": args.cache_condition,
        "environment_sha256": environment_identity(root, command),
        "nix_configuration": nix_configuration(root),
        "expected_runs": args.runs,
        "system_path": None,
        "installable": None,
        "build_receipt_sha256": None,
        "active_system_before": None,
        "active_system_after": None,
        "command_sha256": digest(
            json.dumps([arg.replace(str(root), "<SOURCE>") for arg in command]).encode()
        ),
        "measurements": [],
        "status": "failed",
        "limitations": [
            "Peak RSS is wait4 maximum, not aggregate process-tree memory.",
            "Cache condition is an operator declaration; this command does not clear caches.",
            "Resource measurements exclude Nix daemon and remote builder usage.",
            "Effective Nix configuration describes the client; daemon and remote settings remain outside this observation.",
            "Candidate evaluation and realization checks each have a separate 120-second timeout.",
            "Commands must finish synchronously; processes that create another session escape group cleanup.",
            "Source and active-generation checks observe endpoints, not transient changes during execution.",
        ],
    }


def execute_capture(
    args: argparse.Namespace,
    command: list[str],
    output: Path,
    identifier: str,
    record: dict[str, Any],
) -> None:
    """Collect a candidate, command results and post-execution provenance.

    Raises:
        ValueError: System evidence or source state is inconsistent.

    """
    record.update(candidate_path(args, record["source"]))
    system_path = record["system_path"]
    runtime = args.phase in {"runtime", "recovery"}
    if args.phase in SYSTEM_PHASES:
        record["active_system_before"] = active_generation()
    if runtime and not runtime_matches(system_path, ACTIVE_SYSTEM):
        raise ValueError("The specified built system is not the active generation")
    run_trials(args, command, output, identifier, record)
    if args.phase in SYSTEM_PHASES:
        record["active_system_after"] = active_generation()
    successful = len(record["measurements"]) == args.runs and all(
        valid_sample(sample) for sample in record["measurements"]
    )
    if args.phase == "build" and system_path and successful:
        nix_output(args.source.resolve(), "path-info", system_path)
    verify_configuration_stability(record, args.source.resolve())
    after = source_identity(args.source.resolve())
    if record["source"] != after:
        record["source_after"] = after
        raise ValueError("Tracked source changed during execution")
    if (runtime or args.phase == "activation") and not runtime_matches(
        system_path, ACTIVE_SYSTEM
    ):
        raise ValueError(
            "Active generation does not match the candidate after execution"
        )
    if (
        args.phase == "dry-activation"
        and record["active_system_before"] != record["active_system_after"]
    ):
        raise ValueError("Dry activation changed the active system generation")
    if successful and "reason" not in record:
        record["status"] = "passed"
    else:
        record.setdefault(
            "reason", "Command failed, timed out or left background work running"
        )


def validate_placement(args: argparse.Namespace, command: list[str]) -> None:
    """Enforce the desktop full-system recipe and its existing resource scope.

    Raises:
        ValueError: A desktop build is on the wrong host or outside its runner.

    """
    if args.phase != "build" or args.target != "desktop":
        return
    if platform.node().split(".")[0] != "desktop":
        raise ValueError(
            "Build the desktop system on desktop through just os-build desktop"
        )
    if args.check != "full-system":
        return
    if Path(command[0]).name != "just" or command[1:3] != ["os-build", "desktop"]:
        raise ValueError(
            "Record desktop full-system builds with -- just os-build desktop"
        )
    cgroup = Path("/proc/self/cgroup")
    if not cgroup.exists() or "/background-workload.slice/" not in cgroup.read_text(
        encoding="utf-8"
    ):
        raise ValueError(
            "Run desktop build evidence through workstation-task or just desktop-validation-build"
        )


def verification_diagnostics(error: Exception) -> dict[str, str]:
    """Keep bounded private diagnostics when verification fails before a command log.

    Returns:
        Exception details and available subprocess output, clipped independently.

    """
    limit = 65536
    result = {"exception": type(error).__name__, "message": str(error)[:limit]}
    for name in ("stdout", "stderr"):
        value = getattr(error, name, None)
        if value is not None:
            text = (
                value.decode(errors="replace")
                if isinstance(value, bytes)
                else str(value)
            )
            result[name] = text[:limit] + ("\n[truncated]" if len(text) > limit else "")
    return result


def capture(args: argparse.Namespace) -> tuple[Path, dict[str, Any]]:
    """Execute a bounded check and preserve verification failures as receipts.

    Returns:
        The private receipt path and completed observation.

    Raises:
        ValueError: The command is empty or violates desktop build placement.

    """
    root = args.source.resolve()
    output = private_directory(args.output, root)
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        raise ValueError("Provide a command after --")
    validate_placement(args, command)
    identifier = f"{datetime.now(UTC):%Y%m%dT%H%M%S}-{uuid.uuid4().hex}"
    receipt = output / f"{identifier}.json"
    record = new_record(args, command)
    try:
        execute_capture(args, command, output, identifier, record)
    except ValueError as error:
        record.update(status="invalid", reason=str(error))
    except (subprocess.SubprocessError, OSError) as error:
        record.update(
            status="failed", reason=f"Verification failed: {type(error).__name__}"
        )
        diagnostic = output / f"{identifier}-verification.json"
        write_json(diagnostic, verification_diagnostics(error))
        record["verification_log"] = diagnostic.name
    record["finished"] = now()
    validate_receipt(record)
    write_json(receipt, record)
    return receipt, record


def environment_identity(root: Path, command: list[str]) -> str:
    """Identify the private benchmark environment without exposing its hostname.

    Returns:
        A hash of machine, kernel, CPU inventory, executable and Nix settings.

    """
    cpu = Path("/proc/cpuinfo")
    inventory = cpu.read_bytes() if cpu.exists() else platform.processor().encode()
    # Drop dynamic Linux clock values while retaining processor/model inventory.
    stable = b"\n".join(
        line for line in inventory.splitlines() if not line.startswith(b"cpu MHz")
    )
    executable = ""
    if command:
        selected = shutil.which(command[0])
        if selected:
            executable = str(Path(selected).resolve()).replace(str(root), "<SOURCE>")
    settings = {
        key: os.environ.get(key, "").replace(str(root), "<SOURCE>")
        for key in ("NIX_CONFIG", "NIX_REMOTE", "NIX_PATH", "NIX_BUILD_HOOK")
    }
    return digest(
        json.dumps(
            {
                "machine": platform.node(),
                "kernel": platform.release(),
                "architecture": platform.machine(),
                "cpu": stable.decode(errors="replace"),
                "executable": executable,
                "nix_settings": settings,
            },
            sort_keys=True,
        ).encode()
    )


def valid_digest(value: object) -> bool:
    """Recognize a complete SHA-256 fingerprint.

    Returns:
        Whether the value is a lowercase hexadecimal digest.

    """
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def store_path(value: object) -> bool:
    """Recognize a top-level Nix store output without filesystem access.

    Returns:
        Whether the value names a canonical store output.

    """
    return (
        isinstance(value, str)
        and re.fullmatch(
            r"/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[A-Za-z0-9+_.?=-]+", value
        )
        is not None
    )


def validate_source(source: object) -> None:
    """Validate the complete recursive source identity, including lockfiles.

    Raises:
        ValueError: Source provenance is incomplete or malformed.

    """
    if not isinstance(source, dict) or not (
        isinstance(source.get("revision"), str)
        and re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", source["revision"])
        and valid_digest(source.get("tree_sha256"))
        and type(source.get("dirty")) is bool
        and isinstance(source.get("lockfiles"), dict)
        and isinstance(source.get("submodules"), dict)
    ):
        raise ValueError("Evidence lacks complete tracked source provenance")
    if any(
        not isinstance(name, str) or not name or not valid_digest(value)
        for name, value in source["lockfiles"].items()
    ):
        raise ValueError("Evidence contains an invalid lockfile fingerprint")
    for name, submodule in source["submodules"].items():
        if not isinstance(name, str) or not name:
            raise ValueError("Evidence contains an invalid submodule name")
        validate_source(submodule)


def finite_number(value: object, *, positive: bool = False) -> bool:
    """Recognize finite measurements without accepting Boolean values as numbers.

    Returns:
        Whether a measurement is finite and nonnegative, or strictly positive.

    """
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    try:
        finite = math.isfinite(value)
    except OverflowError:
        return False
    return finite and (value > 0 if positive else value >= 0)


def sample_structure(sample: object) -> bool:
    """Check all measurement fields, including unsuccessful observations.

    Returns:
        Whether the observation has valid resource values and outcome types.

    """
    return isinstance(sample, dict) and (
        type(sample.get("exit_code")) is int
        and type(sample.get("timed_out")) is bool
        and type(sample.get("descendants_remained")) is bool
        and all(
            finite_number(sample.get(field))
            for field in (
                "elapsed_seconds",
                "peak_rss_kib",
                "user_seconds",
                "system_seconds",
            )
        )
        and isinstance(sample.get("log"), str)
        and bool(sample["log"])
        and Path(sample["log"]).name == sample["log"]
        and sample["log"] not in {".", ".."}
    )


def valid_sample(sample: dict[str, Any]) -> bool:
    """Check the outcomes and resource values required for successful evidence.

    Returns:
        Whether a complete sample can support a success claim or comparison.

    """
    return sample_structure(sample) and (
        sample["exit_code"] == 0
        and not sample["timed_out"]
        and not sample["descendants_remained"]
        and all(
            finite_number(sample[field], positive=True)
            for field in ("elapsed_seconds", "peak_rss_kib")
        )
    )


def validate_nix_configuration(configuration: object) -> None:
    """Distinguish measured Nix configuration from an unavailable observation.

    Raises:
        ValueError: Configuration provenance is malformed.

    """
    captured = isinstance(configuration, dict) and (
        configuration.get("status") == "captured"
        and valid_digest(configuration.get("sha256"))
    )
    unavailable = isinstance(configuration, dict) and (
        configuration.get("status") == "unavailable"
        and isinstance(configuration.get("reason"), str)
        and bool(configuration["reason"])
    )
    if not captured and not unavailable:
        raise ValueError("Evidence lacks a valid Nix configuration observation")


def validate_envelope(record: object) -> None:
    """Validate common receipt fields independently of the claimed outcome.

    Raises:
        ValueError: The record lacks its identity, timing or workload fields.

    """
    if (
        not isinstance(record, dict)
        or type(record.get("schema")) is not int
        or (record["schema"] != SCHEMA)
    ):
        raise ValueError("Evidence is missing its supported schema")
    if any(
        not isinstance(record.get(field), str) or not record[field]
        for field in (
            "target",
            "check",
            "system",
            "date",
            "finished",
            "phase",
            "status",
            "cache_condition",
        )
    ):
        raise ValueError("Evidence is missing required workload or date fields")
    if (
        record.get("phase") not in PHASES
        or record["status"] not in {"passed", "failed", "invalid", "skipped"}
        or record["cache_condition"] not in {"warm", "cold", "mixed", "unspecified"}
    ):
        raise ValueError("Unsupported evidence phase, status or cache condition")
    if not re.fullmatch(r"[A-Za-z0-9_]+-(?:linux|darwin)", record["system"]):
        raise ValueError("Evidence has an unsupported execution platform")
    date, finished = (
        datetime.fromisoformat(record[field]) for field in ("date", "finished")
    )
    if (
        date.tzinfo is None
        or finished.tzinfo is None
        or not date <= finished <= datetime.now(UTC)
    ):
        raise ValueError(
            "Evidence dates must be ordered timezone-aware past timestamps"
        )
    if any(
        not valid_digest(record.get(field))
        for field in ("command_sha256", "environment_sha256")
    ):
        raise ValueError("Evidence lacks command or environment fingerprints")
    validate_source(record.get("source"))
    validate_nix_configuration(record.get("nix_configuration"))


def validate_system_evidence(record: dict[str, Any]) -> None:
    """Require output and prior build provenance for successful system phases.

    Raises:
        ValueError: The claimed system check lacks its candidate binding.

    """
    installable = record.get("installable")
    if installable is not None and not (
        isinstance(installable, str) and re.fullmatch(r"[A-Za-z0-9_.-]+", installable)
    ):
        raise ValueError("Evidence contains an invalid output attribute")
    if record["status"] != "passed":
        return
    needs_output = (
        record["phase"] in SYSTEM_PHASES
        or (record["check"] == "full-system" and record["phase"] == "build")
        or installable is not None
    )
    if needs_output and (not installable or not store_path(record.get("system_path"))):
        raise ValueError("System evidence requires a realized candidate output")
    if record["phase"] in SYSTEM_PHASES and not valid_digest(
        record.get("build_receipt_sha256")
    ):
        raise ValueError("System evidence requires matching prior build provenance")


def validate_generation_observations(record: dict[str, Any]) -> None:
    """Require recorded generation observations to substantiate a successful phase.

    Raises:
        ValueError: The observed active generation does not support the claimed phase.

    """
    if record["status"] != "passed" or record["phase"] not in SYSTEM_PHASES:
        return
    if any(
        field not in record for field in ("active_system_before", "active_system_after")
    ):
        raise ValueError("System evidence lacks active-generation observations")
    before, after = record["active_system_before"], record["active_system_after"]
    if any(value is not None and not store_path(value) for value in (before, after)):
        raise ValueError("Active-generation observations must name Nix store outputs")
    if record["phase"] in {"runtime", "recovery"} and before != record["system_path"]:
        raise ValueError("Runtime evidence began on a different generation")
    if record["phase"] == "dry-activation":
        if before != after:
            raise ValueError("Dry activation changed the active generation")
    elif after != record["system_path"]:
        raise ValueError("System evidence finished on a different generation")


def validate_receipt(record: dict[str, Any]) -> None:
    """Require complete receipts and reject unsupported claims of success.

    Raises:
        ValueError: The receipt or its observations are incomplete or inconsistent.

    """
    validate_envelope(record)
    samples, expected = record.get("measurements"), record.get("expected_runs")
    if not isinstance(samples, list) or type(expected) is not int or expected < 1:
        raise ValueError("Evidence lacks its expected repetitions and observations")
    if record.get("kind") != ("benchmark" if expected > 1 else "check"):
        raise ValueError("Evidence kind disagrees with its expected repetitions")
    if len(samples) > expected or not all(
        sample_structure(sample) for sample in samples
    ):
        raise ValueError("Evidence contains malformed measurements")
    if record["status"] == "passed":
        if len(samples) != expected or not all(
            valid_sample(sample) for sample in samples
        ):
            raise ValueError(
                "Passed evidence requires complete successful finite measurements"
            )
    elif not isinstance(record.get("reason"), str) or not record["reason"].strip():
        raise ValueError("Unsuccessful evidence must explain its failure or omission")
    if record["status"] == "skipped" and samples:
        raise ValueError("Skipped checks cannot contain executed observations")
    validate_system_evidence(record)
    validate_generation_observations(record)


def validate_manifest(manifest: dict[str, Any]) -> None:
    """Require a nonempty, unambiguous native validation inventory.

    Raises:
        ValueError: Required checks are missing, duplicated or malformed.

    """
    if (
        not isinstance(manifest, dict)
        or type(manifest.get("schema")) is not int
        or manifest["schema"] != SCHEMA
        or not isinstance(manifest.get("checks"), list)
        or not manifest["checks"]
    ):
        raise ValueError("Validation manifest must declare a nonempty check list")
    keys = set()
    for check in manifest["checks"]:
        fields = ("target", "check", "phase", "system")
        if not isinstance(check, dict) or any(
            not isinstance(check.get(field), str) or not check[field]
            for field in fields
        ):
            raise ValueError(
                "Manifest check lacks target, name, phase or native platform"
            )
        key = tuple(check[field] for field in fields)
        if (
            key in keys
            or check["phase"] not in PHASES
            or not re.fullmatch(r"[A-Za-z0-9_]+-(?:linux|darwin)", check["system"])
            or type(check.get("required", True)) is not bool
        ):
            raise ValueError("Duplicate or invalid validation requirement")
        keys.add(key)
    if not any(check.get("required", True) for check in manifest["checks"]):
        raise ValueError("Validation manifest must require at least one check")


def read_receipt(path: Path) -> dict[str, Any]:
    """Read and validate a complete evidence record.

    Returns:
        The structurally valid private receipt.

    """
    result = json.loads(path.read_text(encoding="utf-8"))
    validate_receipt(result)
    return result


def compare(
    baseline: dict[str, Any], candidate: dict[str, Any], budget: float
) -> dict[str, Any]:
    """Compare matched successful repetitions with explicit spread and budget.

    Returns:
        The medians, ranges and budget result for elapsed time and peak RSS.

    Raises:
        ValueError: Reports are incompatible, unsuccessful or lack enough samples.

    """
    validate_receipt(baseline)
    validate_receipt(candidate)
    if not math.isfinite(budget) or budget < 0:
        raise ValueError("Regression budget must be finite and nonnegative")
    if baseline["cache_condition"] not in {"warm", "cold"}:
        raise ValueError("Comparison needs an explicit warm or cold cache condition")
    if (
        baseline["nix_configuration"]["status"] != "captured"
        or candidate["nix_configuration"]["status"] != "captured"
    ):
        raise ValueError(
            "Comparison requires captured effective Nix client configuration"
        )
    fields = (
        "target",
        "check",
        "phase",
        "system",
        "cache_condition",
        "command_sha256",
        "environment_sha256",
        "nix_configuration",
    )
    if any(baseline.get(field) != candidate.get(field) for field in fields):
        raise ValueError(
            "Benchmark workload, phase, platform, environment or cache conditions differ"
        )
    if baseline["status"] != "passed" or candidate["status"] != "passed":
        raise ValueError("Failed or invalid trials cannot support a comparison")
    if min(len(baseline["measurements"]), len(candidate["measurements"])) < MIN_TRIALS:
        raise ValueError(
            "A comparison needs at least three successful trials per source"
        )
    metrics = {}
    passed = True
    for name in ("elapsed_seconds", "peak_rss_kib"):
        left = [sample[name] for sample in baseline["measurements"]]
        right = [sample[name] for sample in candidate["measurements"]]
        old, new = statistics.median(left), statistics.median(right)
        if old <= 0:
            raise ValueError("Baseline measurements must be positive")
        change = (new / old - 1) * 100
        if not all(math.isfinite(value) for value in (old, new, change)):
            raise ValueError("Measurement range exceeds finite comparison arithmetic")
        within = change <= budget
        passed = passed and within
        metrics[name] = {
            "baseline_median": old,
            "candidate_median": new,
            "baseline_range": [min(left), max(left)],
            "candidate_range": [min(right), max(right)],
            "change_percent": change,
            "within_budget": within,
            "ranges_overlap": max(min(left), min(right)) <= min(max(left), max(right)),
        }
    return {
        "schema": SCHEMA,
        "status": "passed" if passed else "failed",
        "baseline_source": baseline["source"],
        "baseline_date": baseline["date"],
        "candidate_date": candidate["date"],
        "workload": {field: baseline[field] for field in fields},
        "candidate_source": candidate["source"],
        "budget_percent": budget,
        "metrics": metrics,
    }


def coverage(
    root: Path, manifest: dict[str, Any], records: list[dict[str, Any]]
) -> dict[str, Any]:
    """Match required evidence to this source, preserving failed and skipped checks.

    Returns:
        Each required check and its latest matching result, or missing status.

    """
    validate_manifest(manifest)
    for record in records:
        validate_receipt(record)
    identity = source_identity(root)
    rows = []
    for check in manifest["checks"]:
        matching = [
            record
            for record in records
            if all(
                record.get(key) == check[key]
                for key in ("target", "check", "phase", "system")
            )
            and record.get("source") == identity
        ]
        latest = max(
            matching,
            key=lambda item: (
                datetime.fromisoformat(item["finished"]),
                {"passed": 0, "skipped": 1, "failed": 2, "invalid": 3}[item["status"]],
            ),
            default=None,
        )
        status = latest["status"] if latest else "missing"
        rows.append({
            **check,
            "status": status,
            "date": latest["date"] if latest else None,
            "finished": latest["finished"] if latest else None,
        })
    return {
        "schema": SCHEMA,
        "source": identity,
        "checks": rows,
        "status": "passed"
        if rows
        and all(row["status"] == "passed" for row in rows if row.get("required", True))
        else "incomplete",
    }


def skip_check(args: argparse.Namespace) -> tuple[Path, dict[str, Any]]:
    """Record a deliberate omission without inventing executed observations.

    Returns:
        The private skipped receipt and its complete provenance.

    Raises:
        ValueError: No meaningful omission reason was supplied.

    """
    if not args.reason.strip():
        raise ValueError("A skipped check requires a reason")
    output = private_directory(args.output, args.source)
    receipt = output / f"{datetime.now(UTC):%Y%m%dT%H%M%S}-{uuid.uuid4().hex}.json"
    record = new_record(args, [])
    record.update(status="skipped", reason=args.reason, finished=now())
    validate_receipt(record)
    write_json(receipt, record)
    return receipt, record


def parser() -> argparse.ArgumentParser:
    """Define the evidence command interface.

    Returns:
        The argument parser with its explicit operation subcommands.

    """
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--source", type=Path, default=Path.cwd())
    commands = cli.add_subparsers(dest="operation", required=True)
    commands.add_parser("source", help="Print the tracked source identity")
    for name in ("run", "benchmark", "skip"):
        run = commands.add_parser(name)
        run.add_argument(
            "--output",
            type=Path,
            default=Path.home() / ".local/state/nix-conf/evidence",
        )
        run.add_argument("--target", required=True)
        run.add_argument("--check", required=True)
        run.add_argument("--phase", choices=PHASES, required=True)
        run.add_argument(
            "--cache-condition",
            choices=("warm", "cold", "mixed", "unspecified"),
            default="unspecified",
        )
        if name == "skip":
            run.add_argument("--reason", required=True)
            run.add_argument(
                "--system", help="Platform of the omitted check; defaults to this host"
            )
            run.set_defaults(runs=1)
            continue
        run.add_argument(
            "--installable",
            help="Root output attribute whose realized path this build proves",
        )
        run.add_argument(
            "--build-receipt",
            type=Path,
            help="Matching successful build receipt required for runtime, recovery and activation",
        )
        run.add_argument("--timeout", type=float, default=7200)
        run.add_argument("--runs", type=int, default=3 if name == "benchmark" else 1)
        run.add_argument("command", nargs=argparse.REMAINDER)
    diff = commands.add_parser("compare")
    diff.add_argument("baseline", type=Path)
    diff.add_argument("candidate", type=Path)
    diff.add_argument("--budget-percent", type=float, required=True)
    status = commands.add_parser("status")
    status.add_argument("manifest", type=Path)
    status.add_argument("records", type=Path, nargs="*")
    return cli


def dispatch(args: argparse.Namespace) -> int:
    """Execute an operation after argument parsing.

    Returns:
        Zero for complete successful evidence; one for failure or missing checks.

    Raises:
        ValueError: Repetition, timeout or regression-budget arguments are invalid.

    """
    if args.operation == "source":
        result = source_identity(args.source)
    elif args.operation in {"run", "benchmark"}:
        if args.runs < 1 or not math.isfinite(args.timeout) or args.timeout <= 0:
            raise ValueError("Runs and timeout must be positive")
        receipt, result = capture(args)
        print(receipt)
        return 0 if result["status"] == "passed" else 1
    elif args.operation == "skip":
        receipt, _ = skip_check(args)
        print(receipt)
        return 1
    elif args.operation == "compare":
        if not math.isfinite(args.budget_percent) or args.budget_percent < 0:
            raise ValueError("Regression budget must not be negative")
        result = compare(
            read_receipt(args.baseline),
            read_receipt(args.candidate),
            args.budget_percent,
        )
    else:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
        result = coverage(
            args.source, manifest, [read_receipt(path) for path in args.records]
        )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result.get("status", "passed") == "passed" else 1


def main() -> int:
    """Report operational errors without presenting them as successful evidence.

    Returns:
        The requested operation's exit status.

    """
    os.umask(0o077)
    cli = parser()
    args = cli.parse_args()
    try:
        return dispatch(args)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        cli.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    sys.exit(main())
