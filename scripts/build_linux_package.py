"""Build one immutable flake snapshot through the caller's workload scope."""

import json
import os
import signal
import subprocess  # ruff: ignore[suspicious-subprocess-import] - fixed Nix executables and argument vectors.
import sys
import time
from pathlib import Path

LINUX_SYSTEMS = {"x86_64-linux", "aarch64-linux"}


class BuildInputError(ValueError):
    """Reject an unsupported platform pair or an invalid archived source."""


def save(path: Path, value: dict) -> None:
    """Replace a job receipt atomically."""
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def archive_paths(value: dict) -> set[str]:
    """Collect independent store sources, including relative inputs' dependencies.

    Returns:
        Store paths that need independent garbage-collection roots.

    Raises:
        BuildInputError: An archived source is outside the Nix store.

    """
    # Relative inputs are included in their parent's source tree. Nix omits
    # their independent path but still reports their external dependencies.
    paths = {value["path"]} if "path" in value else set()
    for dependency in value.get("inputs", {}).values():
        paths.update(archive_paths(dependency))
    if any(Path(path).parent != Path("/nix/store") for path in paths):
        message = "Flake archive returned a non-store source"
        raise BuildInputError(message)
    return paths


def interrupted(number: int, _frame: object) -> None:
    """Propagate cancellation through the receipt finalizer.

    Raises:
        SystemExit: The command received a cancellation signal.

    """
    raise SystemExit(128 + number)


def compiler_budget() -> int:
    """Bound the configured compiler budget by the caller's available CPUs.

    Returns:
        The host job count, with headroom when its setting is automatic.

    """
    # Respect the host setting, including deliberately lower memory budgets.
    # Automatic settings retain CPU headroom and never exceed eight jobs.
    available_cpus = len(os.sched_getaffinity(0))
    configured_cores = int(
        subprocess.check_output(
            ["nix", "config", "show", "cores"],  # ruff: ignore[start-process-with-partial-path] - Nix comes from the caller's managed tool profile.
            text=True,
        )
    )
    return (
        min(configured_cores, available_cpus)
        if configured_cores > 0
        else max(1, min(8, available_cpus * 3 // 4))
    )


def main() -> int:
    """Archive, root and realize one job while retaining its final receipt.

    Returns:
        The build or cancellation exit status.

    Raises:
        BuildInputError: The requested platforms are unsupported.
        SystemExit: A cancellation signal interrupted the job.

    """
    repository, build_system, host_system, package, directory, expression = sys.argv[1:]
    if build_system not in LINUX_SYSTEMS or host_system not in LINUX_SYSTEMS:
        message = "Unsupported Linux build/host platform pair"
        raise BuildInputError(message)
    state = Path(directory)
    started_at = time.time()
    started_monotonic = time.monotonic()
    compiler_jobs = compiler_budget()
    report = {
        "repository": repository,
        "build_system": build_system,
        "host_system": host_system,
        "package": package,
        "compiler_jobs": compiler_jobs,
        "max_jobs": 1,
        "mode": "native" if build_system == host_system else "cross",
        "started_at": started_at,
        "queue_seconds": round(max(0, started_at - state.stat().st_mtime), 2),
        "queue_measurement": "Approximate wait since launcher roots were prepared; filesystem timestamps use wall time.",
        "phase": "archive",
        "status": "running",
    }
    save(state / "status.json", report)
    status = 1
    for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(number, interrupted)
    try:  # ruff: ignore[too-many-statements-in-try-clause] - all job phases share cancellation and receipt finalization.
        with (state / "archive.json").open("w", encoding="utf-8") as output:
            subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed executable; arguments are not shell source.
                [  # ruff: ignore[start-process-with-partial-path] - fixed Nix command from the managed profile.
                    "nix",
                    "flake",
                    "archive",
                    "--json",
                    "--no-update-lock-file",
                    repository,
                ],
                stdout=output,
                check=True,
            )
        archived = json.loads((state / "archive.json").read_text(encoding="utf-8"))
        report.update(source_snapshot=archived["path"], phase="source_roots")
        save(state / "status.json", report)
        for index, source in enumerate(sorted(archive_paths(archived))):
            subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - only validated store source paths are rooted.
                [  # ruff: ignore[start-process-with-partial-path] - fixed Nix command from the managed profile.
                    "nix-store",
                    "--add-root",
                    str(state / f"source-{index}"),
                    "--indirect",
                    "-r",
                    source,
                ],
                stdout=subprocess.DEVNULL,
                check=True,
            )
        report["phase"] = "build"
        command = [
            "nix",
            "build",
            "--json",
            # Keep phase/compiler progress on stderr; stdout is the JSON receipt.
            "--print-build-logs",
            "--max-jobs",
            "1",
            "--cores",
            str(compiler_jobs),
            "--builders",
            "",
            "--option",
            "extra-platforms",
            "i686-linux" if build_system == "x86_64-linux" else "",
            "--out-link",
            str(state / "result"),
            "--impure",
            "--file",
            expression,
            "--argstr",
            "repository",
            archived["path"],
            "--argstr",
            "buildSystem",
            build_system,
            "--argstr",
            "hostSystem",
            host_system,
            "--argstr",
            "package",
            package,
        ]
        report["command"] = command
        save(state / "status.json", report)
        with (state / "outputs.json").open("w", encoding="utf-8") as output:
            status = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - structured Nix arguments.
                command, stdout=output, check=False
            ).returncode
        status = status if status >= 0 else 128 - status
        if status == 0:
            for result in json.loads(
                (state / "outputs.json").read_text(encoding="utf-8")
            ):
                for output in result["outputs"].values():
                    print(output, flush=True)  # ruff: ignore[print] - store paths are the command's stdout interface.
        return status  # ruff: ignore[try-consider-else] - finalization must cover every phase, including receipt parsing.
    except subprocess.CalledProcessError as error:
        status = error.returncode if error.returncode >= 0 else 128 - error.returncode
        return status
    except SystemExit as error:
        # Python treats None as success and a textual exit message as failure.
        # Preserve the original SystemExit while finalizing its numeric receipt.
        status = (
            int(error.code)
            if isinstance(error.code, int)
            else 0
            if error.code is None
            else 1
        )
        raise
    except Exception as error:
        status = 1
        report["error"] = str(error)
        raise
    finally:
        report.update(
            exit_status=status,
            finished_at=time.time(),
            execution_seconds=round(time.monotonic() - started_monotonic, 2),
            status="passed"
            if status == 0
            else "cancelled"
            if status in {129, 130, 143}
            else "failed",
        )
        save(state / "status.json", report)


if __name__ == "__main__":
    raise SystemExit(main())
