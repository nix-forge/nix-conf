"""Dispatch generic services using owner-only configuration outside the store."""

import json
import os
import stat
import sys
from pathlib import Path

PRIVATE_FILE_MODE = 0o600


def main() -> None:
    """Launch a configured private command after checking its file ownership.

    Raises:
        SystemExit: If the configuration or command fails validation.

    """
    if not sys.argv[1:]:
        message = "A private configuration path is required"
        raise SystemExit(message)
    config_path = Path(sys.argv[1])
    if not config_path.is_absolute():
        message = "The private configuration path must be absolute"
        raise SystemExit(message)
    descriptor = os.open(config_path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor) as source:
        metadata = os.fstat(source.fileno())
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != os.getuid()
            or stat.S_IMODE(metadata.st_mode) != PRIVATE_FILE_MODE
            or metadata.st_nlink != 1
        ):
            message = "Workspace configuration must be an owner-only regular file"
            raise SystemExit(message)
        configuration = json.load(source)
    arguments = sys.argv[2:]
    action = arguments[0] if arguments else "status"
    if action in {"service", "health"}:
        if len(arguments[1:]) != 1:
            message = "A service name is required"
            raise SystemExit(message)
        command = configuration[action][arguments[1]]
    elif action == "backup-job":
        command = configuration["backup_job"]
    else:
        command = [*configuration["cli"], *arguments]
    if not command or not Path(command[0]).is_absolute():
        message = "Workspace commands require an absolute executable"
        raise SystemExit(message)
    environment = os.environ.copy()
    environment["WORKSPACE_STATE_DIR"] = configuration["state_directory"]
    environment["WORKSPACE_SOURCE_DIR"] = configuration["source_directory"]
    os.chdir(configuration["source_directory"])
    os.execve(command[0], command, environment)  # ruff: ignore[start-process-with-no-shell] - owner-authorized private command


if __name__ == "__main__":
    main()
