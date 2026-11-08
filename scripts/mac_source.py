"""Export complete Git working trees and run Mac commands against verified snapshots."""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
import re
import shlex
import shutil
import stat
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Explicit argv and quoted remote commands.
import sys
import tempfile
import time
from pathlib import Path, PurePosixPath
from typing import NoReturn

MANIFEST = ".mac-source-manifest.json"
SCHEMA = 1
NIX_COMMAND_PREFIX = 2


class ExportError(ValueError):
    """An export cannot establish the intended source identity."""


def fail(message: str) -> NoReturn:
    """Reject an incomplete or mismatched snapshot.

    Raises:
        ExportError: With the actionable mismatch.

    """
    raise ExportError(message)


def capture(*args: str, cwd: Path | None = None) -> bytes:
    """Run a fixed tool without shell interpolation.

    Returns:
        The successful tool output.

    """
    return subprocess.check_output(args, cwd=cwd, shell=False)  # ruff: ignore[subprocess-without-shell-equals-true] - Explicit argv.


def encoded(value: object) -> bytes:
    """Serialize a stable identity.

    Returns:
        Canonical UTF-8 JSON.

    """
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(value: object) -> str:
    """Bind provenance and all content records.

    Returns:
        SHA-256 of canonical JSON.

    """
    return hashlib.sha256(encoded(value)).hexdigest()


def relative(name: str) -> Path:
    """Require a normalized relative path, never Git metadata.

    Returns:
        A safe snapshot-relative path.

    """
    path = PurePosixPath(name)
    if (
        not name
        or path.is_absolute()
        or str(path) != name
        or any(part in {"..", ".git"} for part in path.parts)
        or name == MANIFEST
    ):
        fail(f"Unsafe export path: {name!r}")
    return Path(name)


def record(root: Path, name: str) -> dict:
    """Inspect bytes, executable mode or a contained symlink.

    Returns:
        The portable content record, independent of timestamps.

    """
    path = root / relative(name)
    for parent in relative(name).parents:
        if (root / parent).is_symlink():
            fail(f"Source parent is a symlink: {name}")
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode):
        target = str(path.readlink())
        normalized = os.path.normpath(str(Path(name).parent / target))
        if (
            Path(target).is_absolute()
            or normalized == ".."
            or normalized.startswith("../")
        ):
            fail(f"Symlink escapes the snapshot: {name}")
        return {"kind": "link", "target": target}
    if not stat.S_ISREG(info.st_mode):
        fail(f"Unsupported source entry: {name}")
    return {
        "kind": "file",
        "executable": bool(info.st_mode & 0o111),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def working_tree(root: Path, includes: list[str]) -> dict:
    """Inventory tracked working bytes and every initialized nested submodule.

    Returns:
        Source provenance and the complete selected file map.

    """
    files = {}
    repositories = {}

    def visit(repository: Path, prefix: Path) -> None:
        if not (repository / ".git").exists():
            fail(f"Submodule is not initialized: {prefix}")
        index = capture("git", "ls-files", "--stage", "-z", cwd=repository)
        repositories[prefix.as_posix()] = {
            "head": capture("git", "rev-parse", "HEAD", cwd=repository)
            .decode()
            .strip(),
            "indexSha256": hashlib.sha256(index).hexdigest(),
        }
        for entry in index.split(b"\0"):
            if not entry:
                continue
            metadata, raw = entry.split(b"\t", 1)
            mode, _, stage = metadata.decode().split()
            if stage != "0":
                fail(f"Resolve index conflicts before export: {prefix}")
            local = relative(os.fsdecode(raw))
            name = (prefix / local).as_posix()
            if mode == "160000":
                visit(repository / local, prefix / local)
            elif (root / name).exists() or (root / name).is_symlink():
                files[name] = record(root, name)

    visit(root, Path())
    for name in includes:
        relative(name)
        owners = [
            prefix
            for prefix in repositories
            if prefix == "." or name.startswith(prefix + "/")
        ]
        owner = max(owners, key=lambda prefix: len(Path(prefix).parts))
        ignored = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed Git query and explicit paths.
            [  # ruff: ignore[start-process-with-partial-path] - Managed Git from the caller profile.
                "git",
                "check-ignore",
                "--no-index",
                "--",
                str(Path(name).relative_to(owner)),
            ],
            cwd=root / owner,
            capture_output=True,
            check=False,
        )
        if ignored.returncode != 1:
            fail(f"Ignored or invalid explicit source: {name}")
        files[name] = record(root, name)
    return {"schema": SCHEMA, "repositories": repositories, "files": files}


def tree_files(root: Path) -> dict:
    """Inspect every exported entry, catching missing, added and redirected files.

    Returns:
        Actual file and symlink records.

    """
    files = {}
    for directory, directories, names in os.walk(root, followlinks=False):
        base = Path(directory)
        for name in list(directories):
            if (base / name).is_symlink():
                directories.remove(name)
                names.append(name)
        for name in names:
            path = (base / name).relative_to(root).as_posix()
            if path != MANIFEST:
                files[path] = record(root, path)
    return files


def mismatch(expected: dict, actual: dict) -> None:
    """Name affected paths rather than burying the difference in a digest."""
    changed = sorted(
        k for k in expected.keys() | actual.keys() if expected.get(k) != actual.get(k)
    )
    if changed:
        fail(
            "Source mismatch (missing, extra, content, mode or symlink): "
            + ", ".join(changed[:20])
        )


def snapshot(root: Path, destination: Path, includes: list[str]) -> str:
    """Copy one complete source selection, checking for concurrent changes.

    Returns:
        The content and provenance identity of the completed snapshot.

    """
    before = working_tree(root, includes)
    destination.mkdir(mode=0o700)
    for name, item in before["files"].items():
        path = destination / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if item["kind"] == "link":
            path.symlink_to(item["target"])
        else:
            shutil.copyfile(root / name, path)
            path.chmod(0o755 if item["executable"] else 0o644)
    mismatch(before["files"], tree_files(destination))
    after = working_tree(root, includes)
    if before != after:
        fail("Working tree changed during export; retry after the writer finishes")
    identity = digest(before)
    (destination / MANIFEST).write_bytes(encoded(before) + b"\n")
    return identity


def verify(root: Path, expected: str) -> dict:
    """Check the manifest against the caller's identity and every actual file.

    Returns:
        Verified snapshot metadata.

    """
    if root.is_symlink() or not root.is_dir() or (root / MANIFEST).is_symlink():
        fail("Require a real snapshot directory and manifest")
    manifest = json.loads((root / MANIFEST).read_text())
    if manifest.get("schema") != SCHEMA or digest(manifest) != expected:
        fail("Snapshot manifest does not match the expected export identity")
    mismatch(manifest["files"], tree_files(root))
    return manifest


def freshness(receipt: dict) -> None:
    """Reject a previous export after any selected source or index change."""
    current = working_tree(Path(receipt["source"]), receipt["includes"])
    if digest(current) != receipt["identity"]:
        fail(
            "Local source changed since export; create a new Mac export before running commands"
        )


def save(path: Path, value: dict) -> None:
    """Replace a private receipt without a partial success record."""
    descriptor, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(encoded(value) + b"\n")
        Path(temporary).replace(path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def export(args: argparse.Namespace) -> None:
    """Publish one immutable Nix store source and copy it to the Mac."""
    if not re.fullmatch(r"[A-Za-z0-9_@.-]+", args.host) or args.host.startswith("-"):
        fail("Require an SSH host alias")
    source = Path(args.source).resolve()
    receipt = Path(args.receipt).absolute()
    if receipt.exists():
        fail("Receipt already exists; choose a new receipt for each export")
    receipt.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="mac-export-") as temporary:
        identity = snapshot(source, Path(temporary) / "source", args.include)
        store = (
            capture(
                "nix",
                "store",
                "add-path",
                "--name",
                "mac-source",
                str(Path(temporary) / "source"),
            )
            .decode()
            .strip()
        )
    if Path(store).parent != Path("/nix/store"):
        fail("Nix did not return an immutable store source")
    verify(Path(store), identity)
    value = {
        "schema": SCHEMA,
        "source": str(source),
        "host": args.host,
        "snapshot": store,
        "identity": identity,
        "includes": args.include,
    }
    # Pin the exact source before transferring. Each receipt owns its GC root.
    capture(
        "nix-store", "--add-root", str(receipt) + ".source", "--indirect", "-r", store
    )
    capture("nix", "copy", "--to", "ssh://" + args.host, store)
    remote(value, ["_verify"])
    freshness(value)
    save(receipt, value)
    sys.stdout.write(str(receipt) + "\n")


def remote(receipt: dict, arguments: list[str]) -> int:
    """Send the trusted current verifier to SSH stdin, never a stale exported copy.

    Returns:
        The remote validation or command exit code.

    """
    command = shlex.join([
        "python3",
        "-",
        *arguments,
        "--snapshot",
        receipt["snapshot"],
        "--expected",
        receipt["identity"],
    ])
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Structured SSH arguments, quoted exactly once.
        ["ssh", "--", receipt["host"], command],  # ruff: ignore[start-process-with-partial-path] - Managed SSH from the caller profile.
        input=Path(__file__).read_bytes(),
        check=False,
    )
    if result.returncode and arguments == ["_verify"]:
        fail("Remote snapshot verification failed; no export receipt published")
    return result.returncode


def run(args: argparse.Namespace) -> int:
    """Validate freshness and remote integrity before allowing the command.

    Returns:
        The command status, or failure if final validation detects drift.

    Raises:
        ExportError: Source selection or remote integrity no longer matches.
        ValueError: The receipt is malformed.
        OSError: Receipt or source access failed.
        subprocess.SubprocessError: A verification tool failed.

    """
    receipt = json.loads(Path(args.receipt).read_text(encoding="utf-8"))
    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        fail("Require a build or test command after --")
    report = {
        "identity": receipt["identity"],
        "command": command,
        "status": "validating",
        "exitCode": 1,
    }
    report_path = Path(args.receipt + ".last-run.json")
    save(report_path, report)
    try:
        freshness(receipt)
        status = remote(receipt, ["_run", "--command-json", json.dumps(command)])
        freshness(receipt)
    except (ExportError, OSError, ValueError, subprocess.SubprocessError) as error:
        report.update(status="failed", error=str(error), finishedAt=time.time())
        save(report_path, report)
        raise
    report.update(
        status="passed" if status == 0 else "failed",
        exitCode=status,
        finishedAt=time.time(),
    )
    save(report_path, report)
    return status


def remote_dispatch(args: argparse.Namespace) -> int:
    """Root and validate an immutable source before any remote command.

    Returns:
        The checked command's exit code.

    """
    if sys.platform != "darwin":
        fail("Remote Mac source commands require Darwin")
    root = Path(args.snapshot)
    if root.parent != Path("/nix/store"):
        fail("Remote commands require an immutable Nix store snapshot")
    roots = Path.home() / ".local/state/nix-conf/mac-sources"
    roots.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not re.fullmatch(r"[0-9a-f]{64}", args.expected):
        fail("Require a SHA-256 snapshot identity")
    # Concurrent default jobs may export the same source. Register its shared
    # remote GC root once instead of racing two nix-store --add-root calls.
    with (roots / ".lock").open("a") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        anchor = roots / args.expected
        if anchor.is_symlink() and anchor.resolve() == root:
            pass
        elif anchor.exists() or anchor.is_symlink():
            fail("Remote GC root conflicts with this snapshot")
        else:
            capture(
                "nix-store",
                "--add-root",
                str(anchor),
                "--indirect",
                "-r",
                str(root),
            )
    if args.mode == "_run":
        command = [
            arg.replace("{source}", str(root)) for arg in json.loads(args.command_json)
        ]
        return execute_verified(root, args.expected, command)
    verify(root, args.expected)
    return 0


def command_program(command: list[str]) -> list[str]:
    """Find the requested program behind optional environment assignments.

    Returns:
        Program and arguments, excluding a plain env prefix.

    """
    executable = 0
    if command and Path(command[0]).name == "env":
        executable = 1
        while executable < len(command) and "=" in command[executable]:
            executable += 1
    return command[executable:]


def nix_installable_indices(program: list[str]) -> list[int]:
    """Separate source selectors from supported Nix subcommands and flag values.

    Returns:
        Positions of flake installables which must name the verified source.

    """
    options = dict.fromkeys(
        (
            "--no-link",
            "--no-write-lock-file",
            "--no-update-lock-file",
            "--impure",
            "--json",
            "--raw",
            "--show-trace",
            "--print-out-paths",
            "--print-build-logs",
            "-L",
            "--keep-going",
            "-k",
            "--keep-failed",
            "-K",
            "--offline",
            "--refresh",
            "--rebuild",
            "--verbose",
            "-v",
            "--quiet",
            "-q",
            "--accept-flake-config",
            "--no-accept-flake-config",
            "--all-systems",
            "--no-build",
        ),
        0,
    )
    options.update({
        "--max-jobs": 1,
        "--cores": 1,
        "--option": 2,
        "--out-link": 1,
        "-o": 1,
        "--log-format": 1,
        "--extra-experimental-features": 1,
        "--experimental-features": 1,
    })
    index = 2
    if (
        len(program) > NIX_COMMAND_PREFIX
        and program[1] == "flake"
        and program[2] in {"check", "metadata", "archive"}
    ):
        index = 3
    elif len(program) < NIX_COMMAND_PREFIX or program[1] not in {
        "build",
        "eval",
        "develop",
    }:
        fail(
            "Nix source verification supports build, eval, develop and flake check/metadata/archive"
        )
    installables = []
    while index < len(program):
        argument = program[index]
        if program[1] == "develop" and argument in {"--command", "-c"}:
            break
        if argument.startswith("-"):
            flag = argument.split("=", 1)[0]
            if flag not in options:
                fail(
                    f"Nix source override or unsupported option: {flag}; use a snapshot installable"
                )
            if "=" in argument and options[flag] == 0:
                fail(f"Unsupported value for Nix switch: {flag}")
            index += options[flag] - ("=" in argument) + 1
        else:
            installables.append(index)
            index += 1
    return installables


def nix_installables(program: list[str]) -> list[str]:
    """Return the source selectors accepted by the Nix flag parser.

    Returns:
        The selected flake argument values.

    """
    return [program[index] for index in nix_installable_indices(program)]


def normalize_nix_source(root: Path, command: list[str]) -> list[str]:
    """Avoid Nix interpreting an absolute flake URL as an opaque store path.

    Returns:
        A copy using slash-free selectors for this verified snapshot root.

    """
    program = command_program(command)
    if not program or Path(program[0]).name != "nix":
        return command
    result = list(command)
    offset = len(command) - len(program)
    for index in nix_installable_indices(program):
        argument = program[index]
        candidate, separator, fragment = argument.removeprefix("path:").partition("#")
        if (root / candidate).resolve() != root:
            fail(
                "Nix installables must select the verified snapshot root; use .#target"
            )
        result[offset + index] = "." + separator + fragment
    return result


def validate_nix_source(root: Path, command: list[str]) -> None:
    """Reject Nix selectors which silently evaluate another source or registry."""
    program = command_program(command)
    if not program or Path(program[0]).name != "nix":
        return
    for argument in nix_installables(program):
        candidate = argument.removeprefix("path:").split("#", 1)[0]
        explicit = (
            argument.startswith("path:")
            or candidate.startswith(("/", "./", "../"))
            or candidate in {".", ".."}
        )
        if not explicit or not (root / candidate).resolve().is_relative_to(root):
            fail(
                "Nix source is outside the verified snapshot or uses a registry; use . or {source}"
            )


def execute_verified(root: Path, expected: str, command: list[str]) -> int:
    """Refuse tampering before launch and invalidate a command that alters source.

    Returns:
        The command's exit code after final validation.

    """
    validate_nix_source(root, command)
    command = normalize_nix_source(root, command)
    verify(root, expected)
    environment = os.environ | {
        "PYTHONDONTWRITEBYTECODE": "1",
        "MAC_SOURCE_ROOT": str(root),
        "MAC_SOURCE_IDENTITY": expected,
    }
    result = subprocess.run(command, cwd=root, env=environment, check=False)  # ruff: ignore[subprocess-without-shell-equals-true] - User-requested argv, no shell.
    verify(root, expected)
    return result.returncode if result.returncode >= 0 else 128 - result.returncode


def default_command(kind: str, arguments: list[str]) -> list[str]:
    """Choose native commands which always consume the freshly verified source.

    Returns:
        An argument vector suitable for the checked remote runner.

    """
    if kind == "check":
        return [
            "nix",
            "build",
            "--no-link",
            "--no-write-lock-file",
            "--max-jobs",
            "2",
            "--cores",
            "4",
            ".#checks.aarch64-darwin.temporary-package-fixes",
            *arguments,
        ]
    if kind == "test":
        return [
            "nix",
            "develop",
            "--no-write-lock-file",
            "--accept-flake-config",
            "--max-jobs",
            "2",
            "--cores",
            "4",
            ".#tests",
            "--command",
            "python3",
            "-m",
            "pytest",
            "-p",
            "no:cacheprovider",
            *(arguments or ["tests/macos"]),
        ]
    return arguments


def deployment_arguments(arguments: list[str]) -> tuple[list[str], list[str]]:
    """Keep the verified target and transport fixed while accepting deploy flags.

    Returns:
        Deploy options and source-preserving Nix build options.

    """
    switches = {
        "--dry-activate",
        "--debug-logs",
        "-d",
        "--no-progress",
        "--no-demarcate-output",
        "--keep-result",
        "-k",
        "--skip-checks",
        "-s",
        "--remote-build",
        "--boot",
        "--test",
        "--checksigs",
        "-c",
        "--interactive",
        "-i",
    }
    values = {
        "--log-dir",
        "--result-path",
        "-r",
        "--fast-connection",
        "--auto-rollback",
        "--magic-rollback",
        "--confirm-timeout",
        "--activation-timeout",
        "--temp-path",
        "--rollback-succeeded",
        "--sudo",
        "--interactive-sudo",
    }
    deploy = []
    index = 0
    while index < len(arguments) and arguments[index] != "--":
        argument = arguments[index]
        flag = argument.split("=", 1)[0]
        if flag not in switches | values:
            fail(f"Unsupported deploy option or target override: {argument}")
        deploy.append(argument)
        if flag in values and "=" not in argument:
            index += 1
            if index >= len(arguments):
                fail(f"Missing deploy option value: {flag}")
            deploy.append(arguments[index])
        index += 1
    extra = arguments[index + 1 :] if index < len(arguments) else []
    if nix_installables(["nix", "build", *extra]):
        fail("Extra build arguments cannot select a different source")
    return deploy, extra


def deploy_verified(
    receipt_path: str,
    configuration: str,
    kind: str,
    arguments: list[str],
    workload_command: str,
) -> int:
    """Keep deploy-rs dry activation and rollback using the verified source.

    Returns:
        The deployment client's status, after final source verification.

    Raises:
        ExportError: Source, node routing or deployment arguments are unsafe.
        ValueError: Nix or receipt metadata cannot be parsed.
        OSError: Receipt or executable access failed.
        subprocess.SubprocessError: Client preparation failed.

    """
    if not re.fullmatch(r"[A-Za-z0-9_-]+", configuration):
        fail("Require a configured Darwin node name")
    flags, extra = deployment_arguments(arguments)
    receipt = json.loads(Path(receipt_path).read_text(encoding="utf-8"))
    receipt["clientRoot"] = receipt_path + ".client"
    report_path = Path(receipt_path + ".last-run.json")
    report = {
        "identity": receipt["identity"],
        "kind": kind,
        "configuration": configuration,
        "arguments": arguments,
        "clientRoot": receipt["clientRoot"],
        "status": "validating",
        "exitCode": 1,
    }
    save(report_path, report)
    try:
        status = deploy_operation(
            receipt, configuration, kind, (flags, extra), workload_command
        )
    except (ExportError, OSError, ValueError, subprocess.SubprocessError) as error:
        report.update(status="failed", error=str(error), finishedAt=time.time())
        save(report_path, report)
        raise
    report.update(
        status="passed" if status == 0 else "failed",
        exitCode=status,
        finishedAt=time.time(),
    )
    save(report_path, report)
    return status


def deploy_operation(
    receipt: dict,
    configuration: str,
    kind: str,
    options: tuple[list[str], list[str]],
    workload_command: str,
) -> int:
    """Queue only local preparation; remote compilation never holds that queue.

    Returns:
        The pinned deploy client's exit status.

    """
    flags, extra = options
    queue = shlex.split(workload_command)
    if os.uname().nodename.split(".", 1)[0] == "desktop" and not queue:
        fail("Desktop deployment preparation requires workstation-task")
    freshness(receipt)
    root = Path(receipt["snapshot"])
    verify(root, receipt["identity"])
    remote(receipt, ["_verify"])
    reference = "path:" + str(root)
    sys.stderr.write("Preparing deploy-rs for the verified snapshot...\n")
    metadata = json.loads(
        capture(
            *queue,
            "nix",
            "eval",
            "--accept-flake-config",
            "--json",
            "--no-write-lock-file",
            reference + "#deploy.nodes." + configuration,
            "--apply",
            "node: { inherit (node) hostname; profileUser = node.profiles.system.user or null; }",
        )
    )
    if (
        metadata.get("hostname") != receipt["host"]
        or metadata.get("profileUser") != "root"
    ):
        fail(
            "Deploy system profile must use the verified Mac hostname and root account"
        )
    outputs = json.loads(
        capture(
            *queue,
            "nix",
            "build",
            "--accept-flake-config",
            "--json",
            "--out-link",
            receipt["clientRoot"],
            "--no-write-lock-file",
            "--max-jobs",
            "1",
            "--cores",
            "2",
            reference + "#deploy-rs",
        )
    )
    if len(outputs) != 1 or set(outputs[0]["outputs"]) != {"out"}:
        fail("Require exactly one deployment client output")
    client = Path(outputs[0]["outputs"]["out"])
    if client.parent != Path("/nix/store"):
        fail("Deployment client must come from the immutable Nix store")
    freshness(receipt)
    remote(receipt, ["_verify"])
    command = [
        str(client / "bin/deploy"),
        "--skip-checks",
        *(["--dry-activate"] if kind == "build" else []),
        *flags,
        "--remote-build",
        "--ssh-user",
        "root",
        "--profile-user",
        "root",
        "--hostname",
        receipt["host"],
        "--ssh-opts",
        "",
        reference + "#" + configuration + ".system",
        "--",
        "--max-jobs",
        "2",
        "--cores",
        "4",
        "--no-write-lock-file",
        *extra,
    ]
    # Scoped PATH interception queues deploy-rs's nested local Nix evaluations.
    # A build against the exact verified remote store bypasses the local queue.
    result = run_deployment_client(root, receipt, command, queue)
    remote(receipt, ["_verify"])
    verify(root, receipt["identity"])
    freshness(receipt)
    return result.returncode if result.returncode >= 0 else 128 - result.returncode


def client_nix_command(
    arguments: list[str], real_nix: str, queue: list[str], store: str
) -> list[str]:
    """Queue local deploy-rs work, leaving exact remote derivation builds unqueued.

    Returns:
        The correctly placed Nix subprocess argument vector.

    """
    stores = [arg.split("=", 1)[1] for arg in arguments if arg.startswith("--store=")]
    for index, argument in enumerate(arguments):
        if argument == "--store":
            if index + 1 >= len(arguments):
                fail("Missing remote store argument")
            stores.append(arguments[index + 1])
    if stores and any(candidate != store for candidate in stores):
        fail("Deploy-rs attempted to use a store outside the verified Mac")
    remote_build = arguments[:1] == ["build"] and bool(stores)
    if remote_build and not any(
        re.fullmatch(r"/nix/store/[^/]+\.drv(?:\^out)?", arg) for arg in arguments
    ):
        fail("Remote build must consume the already evaluated deployment derivation")
    return [*([] if remote_build else queue), real_nix, *arguments]


def client_nix(args: argparse.Namespace) -> int:
    """Execute a pinned client's Nix subprocess with observable queue placement.

    Returns:
        Only reached for type checking; exec replaces the wrapper process.

    """
    arguments = args.command[1:] if args.command[:1] == ["--"] else args.command
    queue = json.loads(os.environ["MAC_DEPLOY_QUEUE"])
    real_nix = os.environ["MAC_DEPLOY_NIX"]
    command = client_nix_command(
        arguments, real_nix, queue, os.environ["MAC_DEPLOY_STORE"]
    )
    with Path(os.environ["MAC_DEPLOY_LOG"]).open("a", encoding="utf-8") as log:
        fcntl.flock(log.fileno(), fcntl.LOCK_EX)
        log.write(
            json.dumps({"argv": arguments, "queued": command[0] != real_nix}) + "\n"
        )
    os.execvp(command[0], command)  # ruff: ignore[start-process-with-no-shell] - Managed queue command or absolute pinned Nix executable.
    return 1


def run_deployment_client(
    root: Path, receipt: dict, command: list[str], queue: list[str]
) -> subprocess.CompletedProcess:
    """Intercept only this deploy client's local Nix calls, without global wrappers.

    Returns:
        The deploy-rs result after its scoped launcher has been cleaned up.

    """
    real_nix = shutil.which("nix")
    if not real_nix:
        fail("Nix is unavailable for deployment")
    with tempfile.TemporaryDirectory(
        prefix=".deploy-tools-", dir=Path(receipt["clientRoot"]).parent
    ) as directory:
        shim = Path(directory) / "nix"
        shim.write_text(
            "#!/bin/sh\nexec "
            + shlex.join([
                sys.executable,
                str(root / "scripts/mac_source.py"),
                "_client-nix",
                "--",
            ])
            + ' "$@"\n',
            encoding="utf-8",
        )
        shim.chmod(0o700)
        environment = os.environ | {
            "PATH": directory + os.pathsep + os.environ["PATH"],
            "MAC_DEPLOY_QUEUE": json.dumps(queue),
            "MAC_DEPLOY_NIX": str(Path(real_nix).resolve()),
            "MAC_DEPLOY_STORE": "ssh-ng://root@" + receipt["host"],
            "MAC_DEPLOY_LOG": receipt["clientRoot"] + ".nix.jsonl",
        }
        return subprocess.run(command, env=environment, check=False)  # ruff: ignore[subprocess-without-shell-equals-true] - Pinned deploy client with scoped immutable-source launcher.


def automatic(args: argparse.Namespace) -> int:
    """Create a fresh export for each default build, test or deployment command.

    Returns:
        The verified native command's exit status.

    """
    arguments = args.command[1:] if args.command[:1] == ["--"] else args.command
    state = (
        Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
        / "nix-conf/mac-source-runs"
    )
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix=args.kind + "-", dir=state))
    receipt = str(directory / "export.json")
    with contextlib.redirect_stdout(sys.stderr):
        export(
            argparse.Namespace(
                source=args.source, host=args.host, receipt=receipt, include=[]
            )
        )
    if args.kind in {"build", "deploy"}:
        return deploy_verified(
            receipt, args.configuration, args.kind, arguments, args.workload_command
        )
    return run(
        argparse.Namespace(
            receipt=receipt, command=default_command(args.kind, arguments)
        )
    )


def dispatch(args: argparse.Namespace) -> int:
    """Run one parsed source workflow.

    Returns:
        The operation exit status.

    """
    if args.mode == "export":
        export(args)
        return 0
    if args.mode == "_client-nix":
        return client_nix(args)
    if args.mode == "auto":
        return automatic(args)
    if args.mode == "run":
        return run(args)
    return remote_dispatch(args)


def main() -> int:
    """Dispatch export, checked execution, or the trusted SSH verifier.

    Returns:
        Zero on complete verification, otherwise an actionable failure.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    create = modes.add_parser("export")
    create.add_argument("--source", default=".")
    create.add_argument("--host", default="macbook")
    create.add_argument("--receipt", required=True)
    create.add_argument("--include", action="append", default=[])
    auto = modes.add_parser("auto")
    auto.add_argument("--source", default=".")
    auto.add_argument("--host", default="macbook")
    auto.add_argument(
        "--kind", choices=["command", "check", "test", "build", "deploy"], required=True
    )
    auto.add_argument("--configuration", default="macbook-pro-m4")
    auto.add_argument("--workload-command", default="")
    auto.add_argument("command", nargs=argparse.REMAINDER)
    execute = modes.add_parser("run")
    execute.add_argument("--receipt", required=True)
    execute.add_argument("command", nargs=argparse.REMAINDER)
    internal = modes.add_parser("_client-nix")
    internal.add_argument("command", nargs=argparse.REMAINDER)
    for mode in ("_verify", "_run"):
        target = modes.add_parser(mode)
        target.add_argument("--snapshot", required=True)
        target.add_argument("--expected", required=True)
        if mode == "_run":
            target.add_argument("--command-json", required=True)
    args = parser.parse_args()
    try:
        return dispatch(args)
    except (
        ExportError,
        OSError,
        ValueError,
        KeyError,
        TypeError,
        subprocess.SubprocessError,
    ) as error:
        sys.stderr.write(f"mac-source: {error}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
