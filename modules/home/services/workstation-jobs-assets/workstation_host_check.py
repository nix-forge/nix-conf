"""Preserve host file identities inside an existing bounded, daemon-free scope."""
# Fixed native argv owns namespace setup; user data is decoded only after dropping root.
# ruff: file-ignore[subprocess-without-shell-equals-true, suspicious-subprocess-import, start-process-with-no-shell]

import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

MIB = 1024**2
ENTRY_ARGUMENTS = 3


def reject(message: str) -> None:
    """Reject an execution that cannot retain the bounded-host contract.

    Raises:
        ValueError: A required identity or allocation is absent.

    """
    raise ValueError(message)


def allocation(config: dict, group: str, root: Path = Path("/sys/fs/cgroup")) -> None:
    """Validate the inherited native scope before any privileged namespace work."""
    uid = config["uid"]
    prefix = f"/user.slice/user-{uid}.slice/user@{uid}.service/"
    if (
        not group.startswith(prefix)
        or ".." in Path(group).parts
        or "/background-workload.slice/" not in group
        or not re.fullmatch(
            r"workstation-task-bulk-[0-9]+-[0-9]+\.scope", Path(group).name
        )
    ):
        reject("Host checks require their existing workstation bounded scope")
    scope = root / group.lstrip("/")
    maximum = int((scope / "memory.max").read_text(encoding="utf-8"))
    high = int((scope / "memory.high").read_text(encoding="utf-8"))
    if not (
        config["minimumMiB"] * MIB <= maximum <= config["maximumMiB"] * MIB
        and 0 < high < maximum
        and (scope / "memory.swap.max").read_text(encoding="utf-8").strip() == "0"
    ):
        reject("Host checks require a finite qualified RAM cap and zero swap")


def privileged(config_path: str, packet: str) -> None:
    """Create the mount view and irrevocably drop privilege before user decoding."""
    config = json.loads(Path(config_path).read_text(encoding="utf-8"))
    if os.geteuid() != 0 or os.environ.get("SUDO_UID") != str(config["uid"]):
        reject("Only the configured caller may enter the host-check wrapper")
    group = (
        Path("/proc/self/cgroup").read_text(encoding="utf-8").split("::", 1)[1].strip()
    )
    allocation(config, group)
    if not Path(packet).is_absolute():
        reject("An absolute private invocation packet is required")
    if any(stat.S_ISDIR(os.fstat(fd).st_mode) for fd in (0, 1, 2)):
        reject("Host directory descriptors cannot enter the payload")
    command = [
        config["bubblewrap"],
        "--die-with-parent",
        "--unshare-pid",
        "--unshare-ipc",
        "--bind",
        "/",
        "/",
        "--dev-bind",
        "/dev",
        "/dev",
        "--proc",
        "/proc",
        "--ro-bind",
        "/nix/store",
        "/nix/store",
        "--ro-bind",
        "/nix/var/nix",
        "/nix/var/nix",
        "--tmpfs",
        "/nix/var/nix/daemon-socket",
        "--cap-add",
        "CAP_SETUID",
        "--cap-add",
        "CAP_SETGID",
        "--",
        config["setpriv"],
        f"--reuid={config['uid']}",
        f"--regid={config['gid']}",
        "--init-groups",
        "--bounding-set=-all",
        "--inh-caps=-all",
        "--ambient-caps=-all",
        "--no-new-privs",
        "--",
        config["python"],
        "-I",
        str(Path(__file__).resolve()),
        "--payload",
        packet,
        group,
    ]
    os.execv(command[0], command)


def payload(packet: str, expected_group: str) -> None:
    """Decode the caller's environment only as the unprivileged payload user."""
    if os.getuid() == 0 or os.getuid() != os.geteuid():
        reject("Payload must run as the ordinary host user")
    group = (
        Path("/proc/self/cgroup").read_text(encoding="utf-8").split("::", 1)[1].strip()
    )
    if group != expected_group:
        reject("Host-check payload left its admitted scope")
    # The inherited host process group is not visible in the new PID namespace.
    # Give the payload its own session before it can spawn or signal children.
    if os.getpgrp() != os.getpid():
        os.setsid()
    data = json.loads(Path(packet).read_text(encoding="utf-8"))
    os.chdir(data["cwd"])
    os.execvpe(data["argv"][0], data["argv"], data["environment"])


def client(helper: str, command: list[str]) -> int:
    """Carry the exact environment across sudo without interpreting it as root.

    Returns:
        The same finite command's exit code, without retries.

    """
    if not command:
        reject("Missing host-check command")
    with tempfile.TemporaryDirectory(
        prefix="workstation-host-", dir=os.environ["XDG_RUNTIME_DIR"]
    ) as name:
        packet = Path(name) / "invocation.json"
        with packet.open("x", encoding="utf-8") as stream:
            packet.chmod(0o600)
            json.dump(
                {
                    "cwd": str(Path.cwd()),
                    "argv": command,
                    "environment": dict(os.environ),
                },
                stream,
            )
        return subprocess.call(["/run/wrappers/bin/sudo", "-n", helper, str(packet)])


def main() -> int:
    """Dispatch a fixed wrapper entrypoint.

    Returns:
        User command status, or an explicit refusal.

    """
    args = sys.argv[1:]
    if len(args) == ENTRY_ARGUMENTS and args[0] == "--root":
        privileged(args[1], args[2])
    elif len(args) == ENTRY_ARGUMENTS and args[0] == "--payload":
        payload(args[1], args[2])
    elif len(args) >= ENTRY_ARGUMENTS and args[0] == "--client":
        return client(args[1], args[2:])
    else:
        reject("Invalid host-check invocation")
    return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError) as error:
        sys.stderr.write(f"workstation-host-check: {error}\n")
        raise SystemExit(1) from error
