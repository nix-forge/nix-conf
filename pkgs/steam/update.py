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


def _render_finder_icon(app_path: Path, destination: Path) -> None:
    script = (
        "import AppKit\n"
        "import Foundation\n"
        f'let appPath = "{app_path}"\n'
        f'let destination = "{destination}"\n'
        "let image = NSWorkspace.shared.icon(forFile: appPath)\n"
        "image.size = NSSize(width: 1024, height: 1024)\n"
        "guard let tiff = image.tiffRepresentation else { fatalError(\"missing TIFF data\") }\n"
        "guard let bitmap = NSBitmapImageRep(data: tiff) else { fatalError(\"failed to decode TIFF\") }\n"
        "guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError(\"failed to encode PNG\") }\n"
        "try png.write(to: URL(fileURLWithPath: destination))\n"
    )
    _run_checked(
        [
            _get_binary("swift"),
            "-e",
            script,
        ],
        error_message="failed to render the Finder-resolved Steam icon",
    )


def _build_icns_from_png(png_path: Path, destination: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="steam-iconset-") as temp_dir:
        iconset_dir = Path(temp_dir) / "Steam.iconset"
        iconset_dir.mkdir()

        icon_sizes = {
            "icon_16x16.png": 16,
            "icon_16x16@2x.png": 32,
            "icon_32x32.png": 32,
            "icon_32x32@2x.png": 64,
            "icon_128x128.png": 128,
            "icon_128x128@2x.png": 256,
            "icon_256x256.png": 256,
            "icon_256x256@2x.png": 512,
            "icon_512x512.png": 512,
            "icon_512x512@2x.png": 1024,
        }

        for filename, size in icon_sizes.items():
            _run_checked(
                [
                    _get_binary("sips"),
                    "--resampleHeightWidth",
                    str(size),
                    str(size),
                    str(png_path),
                    "--out",
                    str(iconset_dir / filename),
                ],
                error_message=f"failed to create {filename} for Steam.icns",
            )

        _run_checked(
            [
                _get_binary("iconutil"),
                "--convert",
                "icns",
                "--output",
                str(destination),
                str(iconset_dir),
            ],
            error_message="failed to assemble Steam.icns from the Finder-rendered icon",
        )


def _generate_tahoe_icon(app_path: Path, destination: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="steam-finder-icon-") as temp_dir:
        png_path = Path(temp_dir) / "Steam.png"
        _render_finder_icon(app_path, png_path)
        _build_icns_from_png(png_path, destination)


def _validate_appdmg(url: str) -> tuple[str, bytes]:
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
        app_bundle = _find_required_file(extract_root, "Steam.app/Contents/Info.plist").parents[1]

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

        tahoe_icon_path = Path(temp_dir) / "Steam.icns"
        _generate_tahoe_icon(app_bundle, tahoe_icon_path)
        return version, tahoe_icon_path.read_bytes()


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


def _write_binary_atomic(path: Path, content: bytes) -> None:
    temp_path = path.with_name(f"{path.name}.tmp")
    temp_path.write_bytes(content)
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
    icon_path = Path(__file__).with_name("Steam.icns")

    manifest = _fetch_text(MANIFEST_URLS[args.channel], label=f"Steam {args.channel} manifest")
    appdmg_url = _parse_manifest(manifest)
    version, icon_bytes = _validate_appdmg(appdmg_url)

    new_content = _render_source(
        version,
        appdmg_url,
        _prefetch_hash(appdmg_url),
    )
    old_content = source_path.read_text(encoding="utf-8")
    old_icon_bytes = icon_path.read_bytes() if icon_path.exists() else b""

    source_changed = new_content != old_content
    icon_changed = icon_bytes != old_icon_bytes

    if not source_changed and not icon_changed:
        _stdout(f"[update] steam {args.channel} is already up to date")
        return 0

    diff_text = _build_diff(old_content, new_content, source_path) if source_changed else ""
    if diff_text:
        sys.stdout.write(diff_text)
    if icon_changed:
        _stdout(f"[update] Steam Tahoe icon would be updated at {icon_path}")

    if args.check:
        return 1
    if args.dry_run:
        return 0

    if source_changed:
        _write_atomic(source_path, new_content)
    if icon_changed:
        _write_binary_atomic(icon_path, icon_bytes)
    _stdout(f"[update] updated steam from the {args.channel} channel")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
