#!/usr/bin/env python3
"""Update ``ttf-ms-win11-auto`` from the upstream AUR PKGBUILD."""

from __future__ import annotations

import argparse
import base64
import contextlib
import difflib
import os
import re
import shlex
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Final, NoReturn
from urllib.error import URLError
from urllib.parse import urlparse
from urllib.request import urlopen

if TYPE_CHECKING:
    from collections.abc import Sequence


DEFAULT_PKGBUILD_URL: Final = (
    "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=ttf-ms-win11-auto"
)
FONT_ARRAY_NAMES: Final = (
    "_ttf_ms_win11",
    "_ttf_ms_win11_japanese",
    "_ttf_ms_win11_korean",
    "_ttf_ms_win11_sea",
    "_ttf_ms_win11_thai",
    "_ttf_ms_win11_zh_cn",
    "_ttf_ms_win11_zh_tw",
    "_ttf_ms_win11_other",
)
TARGET_ARRAY_NAMES: Final = {*FONT_ARRAY_NAMES, "_sha256sums"}


@dataclass(frozen=True)
class _UpstreamState:
    version: str
    iso_url: str
    iso_hash_sri: str
    font_files: list[str]


def _stdout(message: str) -> None:
    sys.stdout.write(f"{message}\n")


def _stderr(message: str) -> None:
    sys.stderr.write(f"{message}\n")


def _fail(message: str) -> NoReturn:
    _stderr(f"error: {message}")
    raise SystemExit(1)


def _fetch_text(url: str, timeout: int = 30) -> str:
    parsed_url = urlparse(url)
    if parsed_url.scheme != "https":
        _fail(f"unsupported URL scheme for PKGBUILD fetch: {parsed_url.scheme!r}")

    try:
        with urlopen(url, timeout=timeout) as response:
            return response.read().decode("utf-8")
    except URLError as exc:
        _fail(f"failed to fetch PKGBUILD from {url}: {exc}")


def _parse_scalar(pattern: str, text: str, label: str) -> str:
    match = re.search(pattern, text, flags=re.MULTILINE)
    if not match:
        _fail(f"could not parse {label} from PKGBUILD")

    return match.group(1)


def _parse_quoted_scalar(name: str, text: str) -> str:
    match = re.search(
        rf"^\s*{re.escape(name)}=(?:\"([^\"]+)\"|'([^']+)')\s*$",
        text,
        flags=re.MULTILINE,
    )
    if not match:
        _fail(f"could not parse {name} from PKGBUILD")

    value = match.group(1) or match.group(2)
    if value is None:
        _fail(f"could not parse {name} from PKGBUILD")

    return value


def _strip_comment(line: str) -> str:
    return line.split("#", 1)[0].strip()


def _parse_arrays(text: str) -> dict[str, list[str]]:
    arrays: dict[str, list[str]] = {}
    current_name: str | None = None
    current_values: list[str] = []

    for raw_line in text.splitlines():
        if current_name is None:
            start_match = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*)=\((.*)$", raw_line)
            if not start_match:
                continue

            array_name = start_match.group(1)
            if array_name not in TARGET_ARRAY_NAMES:
                continue

            current_name = array_name
            remainder = _strip_comment(start_match.group(2))

            if ")" in remainder:
                before_close = remainder.split(")", 1)[0].strip()
                current_values = shlex.split(before_close) if before_close else []
                arrays[current_name] = current_values
                current_name = None
                current_values = []
            else:
                current_values = shlex.split(remainder) if remainder else []
            continue

        line_content = _strip_comment(raw_line)
        if ")" in line_content:
            before_close = line_content.split(")", 1)[0].strip()
            if before_close:
                current_values.extend(shlex.split(before_close))
            arrays[current_name] = current_values
            current_name = None
            current_values = []
            continue

        if line_content:
            current_values.extend(shlex.split(line_content))

    if current_name is not None:
        _fail(f"unterminated array {current_name} in PKGBUILD")

    return arrays


def _hex_sha256_to_sri(hex_digest: str) -> str:
    normalized = hex_digest.strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", normalized):
        _fail(f"invalid sha256 hex digest in PKGBUILD: {hex_digest}")

    raw = bytes.fromhex(normalized)
    return f"sha256-{base64.b64encode(raw).decode('ascii')}"


def _parse_upstream_state(pkgbuild_text: str) -> _UpstreamState:
    version = _parse_scalar(r"^\s*pkgver=([^\s#]+)\s*$", pkgbuild_text, "pkgver")
    iso_url = _parse_quoted_scalar("_iso", pkgbuild_text)
    arrays = _parse_arrays(pkgbuild_text)

    checksums = arrays.get("_sha256sums")
    if not checksums:
        _fail("could not parse _sha256sums array from PKGBUILD")

    font_files: list[str] = []
    for name in FONT_ARRAY_NAMES:
        values = arrays.get(name)
        if values is None:
            _fail(f"could not parse font array {name} from PKGBUILD")
        font_files.extend(values)

    return _UpstreamState(
        version=version,
        iso_url=iso_url,
        iso_hash_sri=_hex_sha256_to_sri(checksums[0]),
        font_files=font_files,
    )


def _replace_once(content: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, content, count=1, flags=re.MULTILINE)
    if count != 1:
        _fail(f"could not find unique {label} block in default.nix")

    return updated


def _render_font_block(font_files: list[str]) -> str:
    lines = ["  fontFiles = ["]
    lines.extend(f'    "{font}"' for font in font_files)
    lines.append("  ];")
    return "\n".join(lines)


def _update_expression(content: str, upstream: _UpstreamState) -> str:
    updated = _replace_once(
        content,
        r'^  version = ".*";$',
        f'  version = "{upstream.version}";',
        "version",
    )
    updated = _replace_once(
        updated,
        r'^    url = ".*";$',
        f'    url = "{upstream.iso_url}";',
        "src.url",
    )
    updated = _replace_once(
        updated,
        r'^    hash = ".*";$',
        f'    hash = "{upstream.iso_hash_sri}";',
        "src.hash",
    )

    font_pattern = r"(?ms)^  fontFiles = \[\n.*?^  \];"
    font_block = _render_font_block(upstream.font_files)
    font_updated, count = re.subn(font_pattern, font_block, updated, count=1)
    if count != 1:
        _fail("could not find unique fontFiles block in default.nix")

    return font_updated


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
        "--pkgbuild-url",
        default=DEFAULT_PKGBUILD_URL,
        help="AUR PKGBUILD URL to parse",
    )
    parser.add_argument(
        "--package-file",
        default=str(Path(__file__).resolve().with_name("default.nix")),
        help="path to package default.nix",
    )
    return parser.parse_args(list(argv))


def _main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    package_file = Path(args.package_file).resolve()

    if not package_file.exists():
        _fail(f"default.nix not found at {package_file}")

    pkgbuild_text = _fetch_text(args.pkgbuild_url)
    upstream = _parse_upstream_state(pkgbuild_text)

    original = package_file.read_text(encoding="utf-8")
    updated = _update_expression(original, upstream)

    if original == updated:
        _stdout(f"{package_file}: already up to date")
        return 0

    diff_text = _build_diff(original, updated, package_file)

    if args.dry_run or args.check:
        sys.stdout.write(diff_text)

    if args.check:
        _stderr(f"{package_file}: update required")
        return 1

    if args.dry_run:
        return 0

    _write_atomic(package_file, updated)
    _stdout(f"{package_file}: updated")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
