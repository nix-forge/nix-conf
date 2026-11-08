"""Create a private nixos-anywhere flake for the two-drive desktop install."""

import argparse
import json
import re
import subprocess
from pathlib import Path

DISK_ID = re.compile(r"/dev/disk/by-id/[A-Za-z0-9._+:-]+\Z")


def disk_id(value: str) -> str:
    """Validate a persistent whole-drive path.

    Returns:
        The unchanged path.

    Raises:
        argparse.ArgumentTypeError: The path could name a partition or another location.

    """
    if (
        not DISK_ID.fullmatch(value)
        or value.rsplit("/", 1)[-1] in {".", ".."}
        or re.search(r"-part\d+\Z", value)
    ):
        raise argparse.ArgumentTypeError("use a whole-drive /dev/disk/by-id path")
    return value


def main() -> None:
    """Write an install-only flake without touching either disk."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--system-disk", required=True, type=disk_id)
    parser.add_argument("--data-disk", required=True, type=disk_id)
    parser.add_argument(
        "--source",
        required=True,
        type=Path,
        help="complete checkout outside target disks",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="new private directory outside target disks",
    )
    args = parser.parse_args()

    if args.system_disk == args.data_disk:
        parser.error("system and data disks must be different")
    source = args.source.resolve(strict=True)
    if not (source / "flake.nix").is_file() or not (source / "flake.lock").is_file():
        parser.error("--source must be a complete flake checkout")
    if not (source / "nix-seal" / "flake.nix").is_file():
        parser.error("--source is missing the nix-seal submodule")
    git_root = subprocess.run(
        ["git", "-C", str(source), "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=False,
    )
    if git_root.returncode != 0 or Path(git_root.stdout.strip()).resolve() != source:
        parser.error("--source must be the root of a Git checkout")
    tracked = subprocess.run(
        [
            "git",
            "-C",
            str(source),
            "ls-files",
            "--error-unmatch",
            "flake.nix",
            "flake.lock",
            "hosts/shared/local/flake/desktop-installer.nix",
            "hosts/nixos/desktop/local/storage/disk-layout.nix",
            "hosts/nixos/desktop/local/storage/deployment.nix",
        ],
        capture_output=True,
        check=False,
    )
    if tracked.returncode != 0:
        parser.error("--source is missing tracked installer configuration files")
    output = args.output.absolute()
    if output == source or source in output.parents:
        parser.error("--output must be outside the source checkout")
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    target = output / "flake.nix"
    template = (
        Path(__file__)
        .with_name("desktop-installer-flake.nix.in")
        .read_text(encoding="utf-8")
    )
    values = {
        "BASE_URL": json.dumps(f"git+{source.as_uri()}?submodules=1"),
        "SYSTEM_DISK": json.dumps(args.system_disk),
        "DATA_DISK": json.dumps(args.data_disk),
    }
    rendered = re.sub(
        r"\b(BASE_URL|SYSTEM_DISK|DATA_DISK)\b",
        lambda match: values[match.group(0)],
        template,
    )
    target.write_text(rendered, encoding="utf-8")
    target.chmod(0o600)
    print(target)
    print(
        "No disk has been inspected or modified. Verify both paths on the installer before running Disko."
    )


if __name__ == "__main__":
    main()
