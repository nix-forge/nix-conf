#!/usr/bin/env python3
"""Update ``microsoft-teams`` from Microsoft's production macOS Teams config."""

from __future__ import annotations

import argparse
import contextlib
import difflib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Final, NoReturn
from urllib.error import URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from pkgs.update_support import HTTPS_CONTEXT

if TYPE_CHECKING:
    from collections.abc import Sequence


EXPECTED_HOST: Final = "statics.teams.cdn.office.net"
CONFIG_HOST: Final = "config.teams.microsoft.com"
CONFIG_URL_TEMPLATE: Final = (
    "https://config.teams.microsoft.com/config/v1/MicrosoftTeams/"
    "{version}?environment=prod&audienceGroup=general&teamsRing=general&agent=TeamsBuilds"
)
DOWNLOAD_URL_TEMPLATE: Final = (
    "https://statics.teams.cdn.office.net/production-osx/{version}/MicrosoftTeams.pkg"
)
HTTP_USER_AGENT: Final = "nix-conf-updater/1.0 (+https://github.com/NixOS/nixpkgs)"
VERSION_PATTERN: Final = re.compile(r"^[0-9]+(?:\.[0-9]+){3}$")
SOURCE_PATTERN: Final = re.compile(
    r"\A\{\n"
    r'  version = "([^"]+)";\n'
    r"  src = \{\n"
    r'    url = "([^"]+)";\n'
    r'    hash = "sha256-[A-Za-z0-9+/=]+";\n'
    r"  \};\n"
    r"\}\n\Z"
)


@dataclass(frozen=True)
class _Release:
    version: str
    url: str


@dataclass(frozen=True)
class _UpstreamState:
    version: str
    url: str
    hash_sri: str


def _stdout(message: str) -> None:
    sys.stdout.write(f"{message}\n")


def _stderr(message: str) -> None:
    sys.stderr.write(f"{message}\n")


def _fail(message: str) -> NoReturn:
    _stderr(f"error: {message}")
    raise SystemExit(1)


def _fetch_json(url: str, *, label: str, timeout: int = 30) -> object:
    parsed_url = urlparse(url)
    if parsed_url.scheme != "https":
        _fail(f"unsupported URL scheme for {label}: {parsed_url.scheme!r}")
    if parsed_url.netloc != CONFIG_HOST:
        _fail(f"unexpected config host for {label}: {parsed_url.netloc!r}")

    try:
        request = Request(url, headers={"User-Agent": HTTP_USER_AGENT})
        with urlopen(request, timeout=timeout, context=HTTPS_CONTEXT) as response:
            return json.load(response)
    except URLError as exc:
        _fail(f"failed to fetch {label} from {url}: {exc}")
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse JSON for {label} from {url}: {exc}")


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
        _fail(f"failed to prefetch Teams pkg hash:\n{detail}")

    try:
        data = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse nix prefetch JSON output: {exc}")

    hash_value = data.get("hash")
    if not isinstance(hash_value, str):
        _fail("nix prefetch JSON did not include a string `hash` field")
    if not re.fullmatch(r"sha256-[A-Za-z0-9+/=]+", hash_value):
        _fail(f"nix prefetch returned an unexpected hash format: {hash_value!r}")

    return hash_value


def _validate_version(version: str) -> None:
    if VERSION_PATTERN.fullmatch(version) is None:
        _fail(f"unexpected Teams version format: {version!r}")


def _validate_download_url(url: str, version: str) -> None:
    parsed_url = urlparse(url)
    if parsed_url.scheme != "https":
        _fail(f"Teams download URL must use HTTPS: {url}")
    if parsed_url.netloc != EXPECTED_HOST:
        _fail(f"unexpected Teams download host: {parsed_url.netloc!r}")

    expected_path = f"/production-osx/{version}/MicrosoftTeams.pkg"
    if parsed_url.path != expected_path:
        _fail(f"unexpected Teams pkg path: {parsed_url.path!r}")


def _parse_existing_version(content: str) -> str:
    version_match = re.search(r'^  version = "([^"]+)";$', content, re.MULTILINE)
    if version_match is None:
        _fail("could not parse the existing Teams source version")

    version = version_match.group(1)
    _validate_version(version)
    return version


def _discover_latest_version(current_version: str) -> str:
    config_url = CONFIG_URL_TEMPLATE.format(version=current_version)
    data = _fetch_json(config_url, label="Microsoft Teams production config")
    if not isinstance(data, dict):
        _fail("Microsoft Teams production config was not a JSON object")

    build_settings = data.get("BuildSettings")
    if not isinstance(build_settings, dict):
        _fail("Microsoft Teams production config did not include BuildSettings")
    webview_canary = build_settings.get("WebView2Canary")
    if not isinstance(webview_canary, dict):
        _fail("Microsoft Teams production config did not include WebView2Canary")
    macos_settings = webview_canary.get("macOS")
    if not isinstance(macos_settings, dict):
        _fail("Microsoft Teams production config did not include macOS settings")
    latest_version = macos_settings.get("latestVersion")
    if not isinstance(latest_version, str):
        _fail("Microsoft Teams production config did not include macOS latestVersion")

    _validate_version(latest_version)
    return latest_version


def _discover_release(current_version: str) -> _Release:
    version = _discover_latest_version(current_version)
    url = DOWNLOAD_URL_TEMPLATE.format(version=version)
    _validate_download_url(url, version)
    return _Release(version=version, url=url)


def _fetch_upstream(release: _Release) -> _UpstreamState:
    return _UpstreamState(
        version=release.version,
        url=release.url,
        hash_sri=_prefetch_hash(release.url),
    )


def _source_matches_release(content: str, release: _Release) -> bool:
    """Return whether generated source metadata already pins this release.

    Returns:
        Whether the source is in the expected form and matches the release.

    """
    match = SOURCE_PATTERN.fullmatch(content)
    if match is None:
        return False

    version, url = match.group(1, 2)
    return (version, url) == (release.version, release.url)


def _render_source(upstream: _UpstreamState) -> str:
    return (
        "{\n"
        f'  version = "{upstream.version}";\n'
        "  src = {\n"
        f'    url = "{upstream.url}";\n'
        f'    hash = "{upstream.hash_sri}";\n'
        "  };\n"
        "}\n"
    )


def _write_atomic(path: Path, content: str) -> None:
    fd, temp_path = tempfile.mkstemp(prefix=f"{path.name}.", dir=path.parent)
    try:
        os.close(fd)
        Path(temp_path).write_text(content, encoding="utf-8", newline="\n")
        Path(temp_path).replace(path)
    finally:
        with contextlib.suppress(OSError):
            Path(temp_path).unlink(missing_ok=True)


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
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print diff but do not write",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit non-zero when updates are available",
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="re-download and re-hash the archive even when release metadata is unchanged",
    )
    return parser.parse_args(list(argv))


def _main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    source_path = Path(__file__).with_name("source.nix")

    old_content = source_path.read_text(encoding="utf-8")
    current_version = _parse_existing_version(old_content)
    release = _discover_release(current_version)
    if not args.refresh and _source_matches_release(old_content, release):
        _stdout("[update] microsoft-teams is already up to date")
        return 0

    new_content = _render_source(_fetch_upstream(release))

    diff_text = _build_diff(old_content, new_content, source_path)
    if diff_text:
        sys.stdout.write(diff_text)

    if args.check:
        return 1

    if args.dry_run:
        return 0

    _write_atomic(source_path, new_content)
    _stdout("[update] updated microsoft-teams")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
