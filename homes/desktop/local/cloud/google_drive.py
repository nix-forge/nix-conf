"""Manage encrypted, writable rclone state without exposing OAuth credentials."""

from __future__ import annotations

import argparse
import configparser
import contextlib
import io
import json
import os
import resource
import shlex
import signal
import stat
import subprocess
import tempfile
import time
from pathlib import Path

from notification_process import run as run_command

NOTICE_INTERVAL = 60
MAX_CLIENT_BYTES = 64 * 1024


def _private_directory(path: Path) -> None:
    """Create private state.

    Raises:
        ValueError: A directory is a symlink or has a foreign owner.

    """
    for part in reversed([path, *path.parents]):
        if part.is_symlink():
            raise ValueError("A managed directory has a symlink component")
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.stat()
    if info.st_uid != os.getuid() or not stat.S_ISDIR(info.st_mode):
        raise ValueError("Managed directory must belong to the current user")
    path.chmod(0o700)


def _private_file(path: Path) -> None:
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
        raise ValueError("Credential state must be a regular file owned by this user")
    if stat.S_IMODE(info.st_mode) & 0o077:
        raise ValueError("Credential state must not grant access to other users")


def _encrypted_file(path: Path) -> None:
    _private_file(path)
    with path.open("rb") as stream:
        if b"RCLONE_ENCRYPT_V0:" not in stream.read(256):
            raise ValueError("Refusing an unencrypted rclone configuration")


def _client_configuration(path: Path) -> str:
    """Parse a Desktop app credential without echoing values.

    Returns:
        The initial rclone configuration.

    Raises:
        ValueError: Credentials or endpoints are invalid.
        TypeError: Client JSON does not contain an object.

    """
    _private_file(path)
    with path.open("rb") as stream:
        raw = stream.read(MAX_CLIENT_BYTES + 1)
    if len(raw) > MAX_CLIENT_BYTES:
        raise ValueError("OAuth client JSON exceeds the supported size")
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise TypeError("Expected an OAuth client object")
    client = data.get("installed", {})
    if not isinstance(client, dict):
        raise TypeError("Expected a Desktop app client object")
    values = [client.get("client_id"), client.get("client_secret")]
    if not all(
        isinstance(value, str) and value and "\n" not in value and "\r" not in value
        for value in values
    ):
        raise ValueError("Expected a Google OAuth Desktop app JSON file")
    if client.get("auth_uri") != "https://accounts.google.com/o/oauth2/auth":
        raise ValueError("Unexpected Google OAuth authorization endpoint")
    if client.get("token_uri") != "https://oauth2.googleapis.com/token":
        raise ValueError("Unexpected Google OAuth token endpoint")
    config = configparser.ConfigParser(interpolation=None)
    config["google-drive"] = {
        "type": "drive",
        "client_id": values[0],
        "client_secret": values[1],
        "scope": "drive",
        "use_trash": "true",
        "skip_shortcuts": "true",
        "skip_gdocs": "true",
    }
    output = io.StringIO()
    config.write(output)
    return output.getvalue()


def _rclone_arguments(policy: dict[str, str], config: Path) -> list[str]:
    # Only the command and secret path enter argv, never the secret itself.
    password_command = shlex.join([
        policy["cat"],
        policy["passwordFile"],
    ])
    return [
        policy["rclone"],
        "--config",
        str(config),
        "--password-command",
        password_command,
        "--ask-password=false",
    ]


def _initialize(policy: dict[str, str]) -> None:
    _private_directory(Path(policy["stateDirectory"]))
    mount = Path(policy["mountDirectory"])
    if not os.path.ismount(mount):
        _private_directory(mount)


def _setup(policy: dict[str, str]) -> None:
    _initialize(policy)
    password = Path(policy["passwordFile"])
    _private_file(password)
    destination = Path(policy["stateDirectory"]) / "rclone.conf"
    if destination.exists() or destination.is_symlink():
        raise ValueError("Configuration already exists; use google-drive reconnect")
    content = _client_configuration(Path(policy["clientFile"]))
    # Plaintext exists only on nix-seal's noswap tmpfs. Only the encrypted
    # configuration is copied to persistent storage, before browser login.
    with tempfile.TemporaryDirectory(
        prefix="google-drive-", dir=policy["runtimeDirectory"]
    ) as tmp:
        seed = Path(tmp) / "rclone.conf"
        seed.write_text(content, encoding="utf-8")
        seed.chmod(0o600)
        subprocess.run(
            [*_rclone_arguments(policy, seed), "config", "encryption", "set"],
            check=True,
        )
        _encrypted_file(seed)
        descriptor = os.open(
            destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600
        )
        with os.fdopen(descriptor, "wb") as output:
            output.write(seed.read_bytes())
            output.flush()
            os.fsync(output.fileno())
    _reconnect(policy)


def _reconnect(policy: dict[str, str]) -> None:
    subprocess.run(
        [policy["systemctl"], "--user", "stop", "google-drive.service"], check=True
    )
    config = Path(policy["stateDirectory"]) / "rclone.conf"
    _encrypted_file(config)
    subprocess.run(
        [*_rclone_arguments(policy, config), "config", "reconnect", "google-drive:"],
        check=True,
    )
    _encrypted_file(config)
    subprocess.run(
        [policy["systemctl"], "--user", "reset-failed", "google-drive.service"],
        check=False,
    )
    subprocess.run(
        [policy["systemctl"], "--user", "start", "google-drive.service"], check=True
    )
    print("Google Drive is connected. Open the Google Drive bookmark in Files.")


def _notify(policy: dict[str, str], body: str) -> None:
    # Notification failures must not stop a mount or lose its upload worker.
    with contextlib.suppress(OSError, subprocess.TimeoutExpired):
        run_command(
            [policy["notify"], "--urgency=critical", "Google Drive", body],
            check=False,
            timeout=10,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def _mount_drive(policy: dict[str, str]) -> int:
    _initialize(policy)
    config = Path(policy["stateDirectory"]) / "rclone.conf"
    _encrypted_file(config)
    _private_file(Path(policy["passwordFile"]))
    mount = Path(policy["mountDirectory"])
    if os.path.ismount(mount) or any(mount.iterdir()):
        raise ValueError("Mount directory must be empty and not already mounted")
    cache = Path(policy["stateDirectory"]) / "vfs-cache"
    _private_directory(cache)
    command = [
        *_rclone_arguments(policy, config),
        "mount",
        "google-drive:",
        str(mount),
        "--cache-dir",
        str(cache),
        "--vfs-cache-mode=full",
        "--vfs-cache-max-size=5Gi",
        "--vfs-cache-min-free-space=10Gi",
        "--buffer-size=8Mi",
        "--transfers=2",
        "--umask=077",
        "--drive-use-trash=true",
        "--drive-skip-shortcuts=true",
        "--drive-skip-gdocs=true",
        "--log-level=ERROR",
    ]
    # Monitor error lines for upload failures while the mount process remains
    # alive. Never repeat filenames or OAuth values in notifications/output.
    with subprocess.Popen(
        command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True
    ) as process:

        def stop(_signum: int, _frame: object) -> None:
            process.terminate()

        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        last_notice = float("-inf")
        if process.stderr is None:
            raise RuntimeError("Missing mount error stream")
        for _line in process.stderr:
            print(
                "Google Drive reported an error; cached uploads are retained.",
                flush=True,
            )
            if time.monotonic() - last_notice >= NOTICE_INTERVAL:
                _notify(
                    policy,
                    "A Drive operation failed. Keep the local cache until uploads finish.",
                )
                last_notice = time.monotonic()
        return process.wait()


def main() -> int:
    """Run the selected operation.

    Returns:
        The operation exit status.

    """
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--policy", required=True, type=Path)
    parser.add_argument(
        "action",
        choices=[
            "init",
            "setup",
            "reconnect",
            "start",
            "stop",
            "status",
            "mount",
            "stopped",
        ],
    )
    args = parser.parse_args()
    policy = json.loads(args.policy.read_text(encoding="utf-8"))
    try:
        if args.action == "init":
            _initialize(policy)
        elif args.action == "setup":
            _setup(policy)
        elif args.action == "reconnect":
            _reconnect(policy)
        elif args.action == "mount":
            return _mount_drive(policy)
        elif args.action == "stopped":
            if os.environ.get("SERVICE_RESULT", "success") != "success":
                _notify(
                    policy,
                    "The Drive mount stopped unexpectedly. Cached uploads remain on disk.",
                )
        else:
            return subprocess.run(
                [policy["systemctl"], "--user", args.action, "google-drive.service"],
                check=False,
            ).returncode
    except TypeError, ValueError, OSError, subprocess.CalledProcessError:
        print(
            "Google Drive setup failed. Check private credentials and encrypted state; no values were printed."
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
