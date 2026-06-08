#!/usr/bin/env python3
"""Update ``libreoffice`` from The Document Foundation's stable releases."""

from __future__ import annotations

import argparse
import contextlib
import difflib
import json
import os
import re
import shutil
import subprocess  # noqa: S404 - updater invokes the trusted local nix executable
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


STABLE_INDEX_URL: Final = "https://download.documentfoundation.org/libreoffice/stable/"
EXPECTED_HOST: Final = "download.documentfoundation.org"
HTTP_USER_AGENT: Final = "nix-conf-updater/1.0 (+https://github.com/NixOS/nixpkgs)"
VERSION_PATTERN: Final = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
ARCHITECTURES: Final = {
    "aarch64-darwin": ("aarch64", "aarch64"),
    "x86_64-darwin": ("x86_64", "x86-64"),
}


@dataclass(frozen=True)
class _Source:
    url: str
    hash_sri: str


@dataclass(frozen=True)
class _UpstreamState:
    version: str
    sources: dict[str, _Source]


def _stdout(message: str) -> None:
    sys.stdout.write(f"{message}\n")


def _stderr(message: str) -> None:
    sys.stderr.write(f"{message}\n")


def _fail(message: str) -> NoReturn:
    _stderr(f"error: {message}")
    raise SystemExit(1)


def _fetch_text(url: str, *, label: str, timeout: int = 30) -> str:
    parsed_url = urlparse(url)
    if parsed_url.scheme != "https" or parsed_url.netloc != EXPECTED_HOST:
        _fail(f"unexpected URL for {label}: {url}")

    try:
        request = Request(url, headers={"User-Agent": HTTP_USER_AGENT})  # noqa: S310
        with urlopen(  # noqa: S310 - scheme and official host are validated above
            request,
            timeout=timeout,
            context=HTTPS_CONTEXT,
        ) as response:
            return response.read().decode("utf-8")
    except URLError as exc:
        _fail(f"failed to fetch {label} from {url}: {exc}")


def _latest_version(index: str) -> str:
    versions = {
        match
        for match in re.findall(r'href="([0-9]+\.[0-9]+\.[0-9]+)/"', index)
        if VERSION_PATTERN.fullmatch(match)
    }
    if not versions:
        _fail("stable release index did not contain any release versions")

    return max(versions, key=lambda value: tuple(map(int, value.split("."))))


def _download_url(version: str, platform: str) -> str:
    directory, suffix = ARCHITECTURES[platform]
    return (
        f"{STABLE_INDEX_URL}{version}/mac/{directory}/"
        f"LibreOffice_{version}_MacOS_{suffix}.dmg"
    )


def _validate_download(url: str, version: str, platform: str) -> None:
    parsed_url = urlparse(url)
    expected_url = _download_url(version, platform)
    if parsed_url.scheme != "https" or parsed_url.netloc != EXPECTED_HOST:
        _fail(f"unexpected LibreOffice download host: {url}")
    if url != expected_url:
        _fail(f"unexpected LibreOffice download path: {url}")


def _get_nix_binary() -> str:
    binary = shutil.which("nix")
    if isinstance(binary, str):
        return binary
    _fail("`nix` executable not found in PATH")


def _prefetch_hash(url: str) -> str:
    completed = subprocess.run(  # noqa: S603 - executable and URL are validated
        [
            _get_nix_binary(),
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
        _fail(f"failed to prefetch LibreOffice DMG hash:\n{detail}")

    try:
        hash_value = json.loads(completed.stdout).get("hash")
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse nix prefetch JSON output: {exc}")

    if not isinstance(hash_value, str) or not hash_value.startswith("sha256-"):
        _fail("nix prefetch did not return an SRI sha256 hash")
    return hash_value


def _parse_existing(content: str) -> _UpstreamState:
    version_match = re.search(r'^  version = "([^"]+)";$', content, re.MULTILINE)
    if version_match is None:
        _fail("could not parse the existing LibreOffice version")

    sources: dict[str, _Source] = {}
    for platform in ARCHITECTURES:
        block_match = re.search(
            rf"    {re.escape(platform)} = \{{\n"
            r'      url = "([^"]+)";\n'
            r'      hash = "([^"]+)";\n'
            r"    \};",
            content,
        )
        if block_match is None:
            _fail(f"could not parse existing source for {platform}")
        sources[platform] = _Source(url=block_match.group(1), hash_sri=block_match.group(2))

    return _UpstreamState(version=version_match.group(1), sources=sources)


def _discover_upstream(existing: _UpstreamState) -> _UpstreamState:
    version = _latest_version(_fetch_text(STABLE_INDEX_URL, label="stable release index"))
    sources: dict[str, _Source] = {}
    for platform in ARCHITECTURES:
        url = _download_url(version, platform)
        _validate_download(url, version, platform)
        existing_source = existing.sources.get(platform)
        hash_sri = (
            existing_source.hash_sri
            if existing_source is not None and existing_source.url == url
            else _prefetch_hash(url)
        )
        sources[platform] = _Source(url=url, hash_sri=hash_sri)
    return _UpstreamState(version=version, sources=sources)


def _render_source(upstream: _UpstreamState) -> str:
    lines = ["{", f'  version = "{upstream.version}";', "  sources = {"]
    for platform in ARCHITECTURES:
        source = upstream.sources[platform]
        lines.extend(
            [
                f"    {platform} = {{",
                f'      url = "{source.url}";',
                f'      hash = "{source.hash_sri}";',
                "    };",
            ]
        )
    lines.extend(["  };", "}", ""])
    return "\n".join(lines)


def _write_atomic(path: Path, content: str) -> None:
    fd, temp_path = tempfile.mkstemp(prefix=f"{path.name}.", dir=path.parent)
    try:
        os.close(fd)
        Path(temp_path).write_text(content, encoding="utf-8", newline="\n")
        Path(temp_path).replace(path)
    finally:
        with contextlib.suppress(OSError):
            Path(temp_path).unlink(missing_ok=True)


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="print diff but do not write")
    parser.add_argument("--check", action="store_true", help="exit non-zero when updates exist")
    return parser.parse_args(list(argv))


def _main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    source_path = Path(__file__).with_name("source.nix")
    old_content = source_path.read_text(encoding="utf-8")
    new_content = _render_source(_discover_upstream(_parse_existing(old_content)))

    if new_content == old_content:
        _stdout("[update] libreoffice is already up to date")
        return 0

    sys.stdout.write(
        "".join(
            difflib.unified_diff(
                old_content.splitlines(keepends=True),
                new_content.splitlines(keepends=True),
                fromfile=str(source_path),
                tofile=str(source_path),
            )
        )
    )
    if args.check:
        return 1
    if not args.dry_run:
        _write_atomic(source_path, new_content)
        _stdout("[update] updated libreoffice")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
