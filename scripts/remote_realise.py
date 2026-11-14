"""Prepare a native remote build locally without queuing its remote wait."""

import argparse
import contextlib
import json
import re
import shlex
import subprocess  # ruff: ignore[suspicious-subprocess-import] - fixed executables with argument vectors.
import sys
from pathlib import Path, PurePosixPath

MAX_COMPILER_JOBS = 16
NATIVE_SYSTEMS = {"x86_64-linux", "aarch64-linux", "x86_64-darwin", "aarch64-darwin"}


def validate_arguments(
    args: argparse.Namespace, parser: argparse.ArgumentParser
) -> None:
    """Reject ambiguous hosts, non-store derivations and invalid root paths."""
    derivation = Path(args.derivation)
    root = PurePosixPath(args.result_root)
    if re.fullmatch(r"[A-Za-z0-9_@.-]+", args.host) is None or args.host.startswith(
        "-"
    ):
        parser.error("Require a hostname or SSH alias")
    if derivation.parent != Path("/nix/store") or derivation.suffix != ".drv":
        parser.error("Require a Nix store derivation")
    if not root.is_absolute() or ".." in root.parts or not root.name:
        parser.error("Require an absolute remote result root")
    if not 1 <= args.cores <= MAX_COMPILER_JOBS:
        parser.error(f"Require 1-{MAX_COMPILER_JOBS} compiler jobs")


class DerivationMetadataError(ValueError):
    """Nix metadata cannot identify the exact requested native derivation."""


def derivation_record(document: object, derivation: Path) -> dict[str, object]:
    """Select one exact derivation from supported Nix metadata formats.

    Returns:
        The validated record used for native placement and closure checks.

    Raises:
        DerivationMetadataError: Metadata cannot identify the requested derivation.

    """
    if not isinstance(document, dict):
        message = "Derivation metadata must be an object"
        raise DerivationMetadataError(message)
    if "version" in document:
        version = document.get("version")
        if (
            set(document) != {"version", "derivations"}
            or not isinstance(version, int)
            or version not in {2, 4}
        ):
            message = "Unsupported derivation metadata envelope"
            raise DerivationMetadataError(message)
        records = document["derivations"]
        key = derivation.name
    else:
        records = document
        key = str(derivation)
    if not isinstance(records, dict) or set(records) != {key}:
        message = "Require exactly the requested derivation"
        raise DerivationMetadataError(message)
    record = records[key]
    if not isinstance(record, dict) or not isinstance(record.get("system"), str):
        message = "Derivation has no valid build system"
        raise DerivationMetadataError(message)
    name = record.get("name")
    if name is None and isinstance(record.get("env"), dict):
        name = record["env"].get("name")
    if name is not None and not isinstance(name, str):
        message = "Derivation has no valid name"
        raise DerivationMetadataError(message)
    return {**record, "name": name or ""}


def main() -> int:
    """Validate placement, queue preparation, and realize on the native host.

    Returns:
        The remote SSH build exit status.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host")
    parser.add_argument("derivation")
    parser.add_argument("result_root")
    parser.add_argument("--cores", type=int, default=8)
    parser.add_argument(
        "--workload-command", default="", help="Shell-quoted local preparation prefix"
    )
    parser.add_argument(
        "--protected-system",
        action="append",
        default=[],
        help="NixOS system name requiring its dedicated build recipe",
    )
    args = parser.parse_args()
    derivation = Path(args.derivation)
    root = PurePosixPath(args.result_root)
    validate_arguments(args, parser)
    queue = shlex.split(args.workload_command)
    cgroup = ""
    if queue:
        # Non-Linux callers can supply their own preparation runner.
        with contextlib.suppress(FileNotFoundError):
            cgroup = Path("/proc/self/cgroup").read_text(encoding="utf-8")
    if queue and "/background-workload.slice/" in cgroup:
        parser.error(
            "Run remote-realise outside workstation-task; preparation queues itself"
        )
    ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", args.host]
    native = subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed executable, argument vectors and quoted SSH command.
        [
            *ssh,
            shlex.join([
                "nix",
                "eval",
                "--impure",
                "--raw",
                "--expr",
                "builtins.currentSystem",
            ]),
        ],
        text=True,
        shell=False,
    ).strip()
    if native not in NATIVE_SYSTEMS:
        parser.error("Unsupported native remote platform")
    descriptions = json.loads(
        subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed executable, argument vectors and quoted SSH command.
            [*queue, "nix", "derivation", "show", str(derivation)],
            text=True,
            shell=False,
        )
    )
    try:
        record = derivation_record(descriptions, derivation)
    except ValueError as error:
        parser.error(str(error))
    if record["system"] != native:
        parser.error("Derivation platform must match the native remote host")
    if any(
        str(record.get("name", "")).startswith(f"nixos-system-{name}-")
        for name in args.protected_system
    ):
        parser.error("Use the dedicated system-build recipe for this protected closure")
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed executable, argument vectors and quoted SSH command.
        [
            *queue,
            "nix",
            "copy",
            "--derivation",
            "--to",
            "ssh://" + args.host,
            str(derivation),
        ],
        check=True,
        shell=False,
    )
    # SSH joins arguments into shell source; quote every remote argument once.
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed executable, argument vectors and quoted SSH command.
        [*ssh, shlex.join(["mkdir", "-p", "--", str(root.parent)])],
        check=True,
        shell=False,
    )
    # This wait has no desktop workload lock. Heavy evaluation and copying
    # above remain queued; compilation and output roots belong to the remote.
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed executable, argument vectors and quoted SSH command.
        [
            *ssh,
            shlex.join([
                "nix-store",
                "--realise",
                str(derivation),
                "--add-root",
                str(root),
                "--indirect",
                "--builders",
                "",
                "--max-jobs",
                "1",
                "--cores",
                str(args.cores),
                "--option",
                "extra-platforms",
                "",
            ]),
        ],
        check=False,
        shell=False,
        stdout=subprocess.PIPE,
        text=True,
    )
    if result.returncode:
        return result.returncode
    # --add-root prints root names. Consumers need store output paths instead.
    outputs = subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed remote query, validated derivation and quoted SSH command.
        [*ssh, shlex.join(["nix-store", "--query", "--outputs", str(derivation)])],
        text=True,
        shell=False,
    ).splitlines()
    if not outputs or any(
        Path(output).parent != Path("/nix/store") for output in outputs
    ):
        parser.error("Remote output query did not return store paths")
    for output in outputs:
        sys.stdout.write(output + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
