"""Exercise the packaged Linux shell loader and child completion in Owl.

Run with the package's lib/chatgpt directory and optionally an SSH host alias.
The optional check uses the package's SSH arguments with a fresh multiplex socket.
Without a host, no account or network connection is required.
"""

import argparse
import json
import os
import struct
import subprocess  # ruff: ignore[suspicious-subprocess-import] - This probe supervises the selected runtime.
import sys
import tempfile
from pathlib import Path

from notification_process import run as run_command
from typescript_sources import javascript_source


def write_archive(path: Path, files: dict[str, bytes]) -> None:
    """Write a small ASAR fixture without relying on an installed Node package."""
    entries = {}
    payload = b""
    for name, content in files.items():
        entries[name] = {"size": len(content), "offset": str(len(payload))}
        payload += content
    header_json = json.dumps({"files": entries}, separators=(",", ":")).encode()
    padding = -len(header_json) % 4
    header = (
        struct.pack("<II", 4 + len(header_json) + padding, len(header_json))
        + header_json
        + b"\0" * padding
    )
    path.write_bytes(struct.pack("<II", 4, len(header)) + header + payload)


def main() -> int:
    """Run the actual upstream shell loader in an isolated native app.

    Returns:
        The probe application's exit status.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runtime", type=Path)
    parser.add_argument("ssh_host", nargs="?")
    arguments = parser.parse_args()
    source = arguments.runtime.resolve()
    with tempfile.TemporaryDirectory(prefix="codex-child-exit-") as directory:
        root = Path(directory)
        runtime = root / "runtime"
        runtime.mkdir()
        for entry in source.iterdir():
            if entry.name == "ChatGPT":
                subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Explicit argv from the selected package.
                    ["cp", "--reflink=auto", str(entry), str(runtime / entry.name)],  # ruff: ignore[start-process-with-partial-path] - Use the caller's coreutils.
                    check=True,
                )
            elif entry.name != "resources":
                (runtime / entry.name).symlink_to(entry)
        resources = runtime / "resources"
        resources.mkdir()
        for entry in (source / "resources").iterdir():
            if entry.name != "app.asar":
                (resources / entry.name).symlink_to(entry)
        main_js = javascript_source(
            Path(__file__).with_name("fixtures") / "ssh-startup.cts"
        )
        write_archive(
            resources / "app.asar",
            {
                "package.json": json.dumps(
                    {
                        "name": "codex-child-exit-check",
                        "version": "1.0.0",
                        "main": "main.cjs",
                    },
                ).encode(),
                "main.cjs": main_js.encode(),
            },
        )
        home = root / "home"
        home.mkdir()
        # The optional integration check uses the caller's SSH configuration.
        if arguments.ssh_host:
            (home / ".ssh").symlink_to(Path.home() / ".ssh")
        environment = {
            "CODEX_TEST_BUNDLE": str(source / "resources/app.asar/.vite/build"),
            "CODEX_TEST_SSH_HOST": arguments.ssh_host or "",
            **os.environ,
            "HOME": str(home),
            "SHELL": "/bin/sh",
            "CODEX_HOME": str(home / "codex"),
            "XDG_CONFIG_HOME": str(home / "config"),
        }
        return run_command(
            [
                str(runtime / "ChatGPT"),
                f"--user-data-dir={root / 'profile'}",
                "--ozone-platform=headless",
                "--disable-gpu",
            ],
            env=environment,
            timeout=15,
            check=False,
        ).returncode


if __name__ == "__main__":
    sys.exit(main())
