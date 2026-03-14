"""Update ``steam`` from Valve's official macOS client manifest."""

from __future__ import annotations

import argparse
import difflib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING, Final, NoReturn
from urllib.error import URLError
from urllib.request import Request, urlopen

if TYPE_CHECKING:
    from collections.abc import Sequence


HTTP_USER_AGENT: Final = "nix-conf-updater/1.0 (+https://github.com/NixOS/nixpkgs)"
MANIFEST_URLS: Final = {
    "stable": "https://media.steampowered.com/client/steam_client_osx",
    "beta": "https://media.steampowered.com/client/steam_client_publicbeta_osx",
}
APPDMG_PACKAGE: Final = "appdmg_osx"


def _stdout(message: str) -> None:
    sys.stdout.write(f"{message}\n")


def _stderr(message: str) -> None:
    sys.stderr.write(f"{message}\n")


def _fail(message: str) -> NoReturn:
    _stderr(f"error: {message}")
    raise SystemExit(1)


def _fetch_text(url: str, *, label: str, timeout: int = 30) -> str:
    try:
        request = Request(url, headers={"User-Agent": HTTP_USER_AGENT})
        with urlopen(request, timeout=timeout) as response:
            return response.read().decode("utf-8")
    except URLError as exc:
        _fail(f"failed to fetch {label} from {url}: {exc}")
    except UnicodeDecodeError as exc:
        _fail(f"failed to decode {label} from {url}: {exc}")


def _get_binary(name: str) -> str:
    binary = shutil.which(name)
    if isinstance(binary, str):
        return binary
    _fail(f"`{name}` executable not found in PATH")


def _prefetch_hash(url: str) -> str:
    completed = subprocess.run(
        [
            _get_binary("nix"),
            "store",
            "prefetch-file",
            "--json",
            "--hash-type",
            "sha256",
            url,
        ],
        capture_output=True,
        check=False,
        text=True,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "(no output)"
        _fail(f"failed to prefetch archive hash:\n{detail}")

    try:
        data = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse nix prefetch JSON output: {exc}")

    hash_value = data.get("hash")
    if not isinstance(hash_value, str):
        _fail("nix prefetch JSON did not include a string `hash` field")
    return hash_value


def _parse_manifest(manifest: str) -> str:
    appdmg_block_match = re.search(
        rf'"{re.escape(APPDMG_PACKAGE)}"\s*'
        r"\{(.*?)\n\}",
        manifest,
        re.DOTALL,
    )
    if appdmg_block_match is None:
        _fail("could not find the macOS appdmg package in the Steam manifest")

    appdmg_files = re.findall(r'"file"\s+"([^"]+)"', appdmg_block_match.group(1))
    appdmg_candidates = [filename for filename in appdmg_files if "steamchina" not in filename]
    if len(appdmg_candidates) != 1:
        _fail("could not uniquely determine the standard macOS appdmg package")
    return f"https://media.steampowered.com/client/{appdmg_candidates[0]}"


def _run_checked(args: list[str], *, error_message: str) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        args,
        capture_output=True,
        check=False,
        text=True,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "(no output)"
        _fail(f"{error_message}:\n{detail}")
    return completed


def _find_required_file(root: Path, suffix: str) -> Path:
    path = next(root.rglob(suffix), None)
    if path is None:
        _fail(f"Steam appdmg payload did not contain {suffix}")
    return path


def _validate_appdmg(url: str) -> str:
    if sys.platform != "darwin":
        _fail("Steam appdmg validation currently requires Darwin")

    with tempfile.TemporaryDirectory(prefix="steam-appdmg-") as temp_dir:
        archive_path = Path(temp_dir) / "appdmg.zip"
        extract_root = Path(temp_dir) / "extract"
        extract_root.mkdir()

        _run_checked(
            [
                _get_binary("curl"),
                "--fail",
                "--location",
                "--silent",
                "--show-error",
                "--output",
                str(archive_path),
                url,
            ],
            error_message="failed to download Steam appdmg payload for validation",
        )

        _run_checked(
            [
                _get_binary("unzip"),
                "-qq",
                str(archive_path),
                "-d",
                str(extract_root),
            ],
            error_message="failed to extract Steam appdmg payload for validation",
        )

        tarball = extract_root / "SteamMacBootstrapper.tar.gz"
        if not tarball.exists():
            _fail("Steam appdmg payload did not contain SteamMacBootstrapper.tar.gz")

        version_path = extract_root / "SteamMacBootstrapper.version"
        if not version_path.exists():
            _fail("Steam appdmg payload did not contain SteamMacBootstrapper.version")

        _run_checked(
            [
                _get_binary("tar"),
                "-xzf",
                str(tarball),
                "-C",
                str(extract_root),
            ],
            error_message="failed to unpack SteamMacBootstrapper.tar.gz",
        )

        _find_required_file(extract_root, "Steam.app/Contents/Resources/Steam.icns")
        _find_required_file(extract_root, "Steam.app/Contents/Resources/Assets.car")
        steam_binary = _find_required_file(extract_root, "Steam.app/Contents/MacOS/steam_osx")
        _find_required_file(extract_root, "Steam.app/Contents/Info.plist")

        inspect = _run_checked(
            [_get_binary("file"), str(steam_binary)],
            error_message="failed to inspect Steam appdmg bootstrap binary",
        )
        output = inspect.stdout
        if "arm64" not in output or "x86_64" not in output:
            _fail("Steam appdmg bootstrap binary is not universal (`arm64` + `x86_64`)")

        version = version_path.read_text(encoding="utf-8").strip()
        if not version:
            _fail("SteamMacBootstrapper.version was empty")
        return version


def _render_source(version: str, appdmg_url: str, appdmg_hash: str) -> str:
    return (
        "{\n"
        f'  version = "{version}";\n'
        "  appdmg = {\n"
        f'    url = "{appdmg_url}";\n'
        f'    hash = "{appdmg_hash}";\n'
        "  };\n"
        "}\n"
    )


def _write_atomic(path: Path, content: str) -> None:
    temp_path = path.with_name(f"{path.name}.tmp")
    temp_path.write_text(content, encoding="utf-8", newline="\n")
    temp_path.replace(path)


def _build_diff(old: str, new: str, path: Path) -> str:
    return "".join(
        difflib.unified_diff(
            old.splitlines(keepends=True),
            new.splitlines(keepends=True),
            fromfile=str(path),
            tofile=str(path),
        ),
    )


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="print diff but do not write")
    parser.add_argument("--check", action="store_true", help="exit non-zero when updates are available")
    parser.add_argument(
        "--channel",
        choices=sorted(MANIFEST_URLS),
        default="stable",
        help="Steam manifest channel to pin",
    )
    return parser.parse_args(list(argv))


def _main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    source_path = Path(__file__).with_name("source.nix")

    manifest = _fetch_text(MANIFEST_URLS[args.channel], label=f"Steam {args.channel} manifest")
    appdmg_url = _parse_manifest(manifest)
    version = _validate_appdmg(appdmg_url)

    new_content = _render_source(
        version,
        appdmg_url,
        _prefetch_hash(appdmg_url),
    )
    old_content = source_path.read_text(encoding="utf-8")
    if new_content == old_content:
        _stdout(f"[update] steam {args.channel} is already up to date")
        return 0

    diff_text = _build_diff(old_content, new_content, source_path)
    if diff_text:
        sys.stdout.write(diff_text)

    if args.check:
        return 1
    if args.dry_run:
        return 0

    _write_atomic(source_path, new_content)
    _stdout(f"[update] updated steam from the {args.channel} channel")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
