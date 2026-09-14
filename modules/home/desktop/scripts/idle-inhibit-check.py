"""Gate Hypridle actions using native window inhibitors, excluding background apps."""

import argparse
import json
import subprocess  # ruff: ignore[suspicious-subprocess-import] - fixed IPC command, without a shell
import sys


def main() -> int:
    """Run the native inhibitor check.

    Returns:
        Zero if the idle action may proceed, one if it should wait.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("screen", "suspend"))
    parser.add_argument("background_classes", nargs="*")
    args = parser.parse_args()
    try:
        result = subprocess.run(
            ["hyprctl", "-j", "clients"],  # ruff: ignore[start-process-with-partial-path] - Nix wrapper pins PATH
            check=True,
            capture_output=True,
            text=True,
            timeout=2,
        )
        clients = json.loads(result.stdout)
        valid = isinstance(clients, list) and not any(
            not isinstance(client, dict)
            or not isinstance(client.get("class"), str)
            or not isinstance(client.get("inhibitingIdle"), bool)
            for client in clients
        )
        if not valid:
            sys.stderr.write(
                "Cannot inspect native idle inhibitors: invalid clients response\n"
            )
            return 0 if args.action == "screen" else 1
    except (OSError, subprocess.SubprocessError, ValueError) as error:
        sys.stderr.write(f"Cannot inspect native idle inhibitors: {error}\n")
        # Protect the screen on IPC failure, but do not suspend unknown work.
        return 0 if args.action == "screen" else 1

    ignored = set(args.background_classes) if args.action == "screen" else set()
    return int(
        any(
            client["inhibitingIdle"] and client["class"] not in ignored
            for client in clients
        )
    )


if __name__ == "__main__":
    sys.exit(main())
