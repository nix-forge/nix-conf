#!/usr/bin/env python3
"""Update ``ttf-ms-win11-auto`` from Microsoft Evaluation Center metadata."""

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
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

if TYPE_CHECKING:
    from collections.abc import Sequence


DEFAULT_EVAL_PAGE_URL: Final = (
    "https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise"
)
ISO_ALIAS_TEMPLATE: Final = "https://aka.ms/Win11E-ISO-{release}-en-us"
HTTP_METHOD_NOT_ALLOWED: Final = 405


@dataclass(frozen=True)
class _UpstreamState:
    version: str
    iso_url: str
    iso_hash_sri: str


def _stdout(message: str) -> None:
    sys.stdout.write(f"{message}\n")


def _stderr(message: str) -> None:
    sys.stderr.write(f"{message}\n")


def _fail(message: str) -> NoReturn:
    _stderr(f"error: {message}")
    raise SystemExit(1)


def _fetch_text(url: str, *, label: str, timeout: int = 30) -> str:
    parsed_url = urlparse(url)
    if parsed_url.scheme != "https":
        _fail(f"unsupported URL scheme for {label}: {parsed_url.scheme!r}")

    try:
        with urlopen(url, timeout=timeout) as response:
            return response.read().decode("utf-8")
    except URLError as exc:
        _fail(f"failed to fetch {label} from {url}: {exc}")


def _parse_release(eval_page_text: str) -> str:
    matches = {
        match.upper()
        for match in re.findall(
            r"\bversion\s+([0-9]{2}H[0-9])\b",
            eval_page_text,
            flags=re.IGNORECASE,
        )
    }
    if not matches:
        _fail(
            "could not detect a Windows 11 release marker "
            "like '25H2' on the eval page",
        )

    def _sort_key(release: str) -> tuple[int, int]:
        parsed = re.fullmatch(r"([0-9]{2})H([0-9])", release)
        if parsed is None:
            _fail(f"invalid release marker parsed from eval page: {release!r}")
        return (int(parsed.group(1)), int(parsed.group(2)))

    return max(matches, key=_sort_key)


def _resolve_iso_url(alias_url: str, *, timeout: int = 30) -> str:
    parsed_alias_url = urlparse(alias_url)
    if parsed_alias_url.scheme != "https":
        _fail(f"unsupported URL scheme for ISO alias: {parsed_alias_url.scheme!r}")

    request = Request(alias_url, method="HEAD")
    try:
        with urlopen(request, timeout=timeout) as response:
            final_url = response.geturl()
    except HTTPError as exc:
        if exc.code != HTTP_METHOD_NOT_ALLOWED:
            _fail(f"failed to resolve ISO alias {alias_url}: {exc}")
        try:
            with urlopen(alias_url, timeout=timeout) as response:
                final_url = response.geturl()
        except URLError as inner_exc:
            _fail(f"failed to resolve ISO alias {alias_url}: {inner_exc}")
    except URLError as exc:
        _fail(f"failed to resolve ISO alias {alias_url}: {exc}")

    parsed_final_url = urlparse(final_url)
    if parsed_final_url.scheme != "https":
        _fail(f"resolved ISO URL does not use HTTPS: {final_url}")
    if not parsed_final_url.path.lower().endswith(".iso"):
        _fail(f"resolved URL is not an ISO download link: {final_url}")

    return final_url


def _derive_version(iso_url: str) -> str:
    iso_name = Path(urlparse(iso_url).path).name
    match = re.match(r"^([0-9]+)\.([0-9]+)\.", iso_name)
    if match is None:
        _fail(f"could not derive package version from ISO filename: {iso_name}")

    return f"10.0.{match.group(1)}.{match.group(2)}"


def _prefetch_iso_hash(iso_url: str) -> str:
    nix_binary = shutil.which("nix")
    if nix_binary is None:
        _fail("`nix` executable not found in PATH")

    command = [
        nix_binary,
        "store",
        "prefetch-file",
        "--json",
        "--hash-type",
        "sha256",
        iso_url,
    ]
    completed = subprocess.run(
        command,
        capture_output=True,
        check=False,
        text=True,
    )
    if completed.returncode != 0:
        stderr_text = completed.stderr.strip()
        stdout_text = completed.stdout.strip()
        detail = stderr_text or stdout_text
        _fail(
            "failed to prefetch ISO hash with nix store prefetch-file:\n"
            f"{detail or '(no output)'}",
        )

    output_text = completed.stdout.strip()
    if not output_text:
        _fail("nix store prefetch-file produced empty output")

    try:
        parsed = json.loads(output_text)
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse nix prefetch JSON output: {exc}")

    hash_value = parsed.get("hash")
    if not isinstance(hash_value, str):
        _fail("nix prefetch JSON did not include a string `hash` field")
    if not re.fullmatch(r"sha256-[A-Za-z0-9+/=]+", hash_value):
        _fail(f"nix prefetch returned an unexpected hash format: {hash_value!r}")

    return hash_value


def _discover_upstream(eval_page_url: str) -> _UpstreamState:
    eval_page_text = _fetch_text(
        eval_page_url,
        label="Windows 11 Evaluation Center page",
    )
    release = _parse_release(eval_page_text)
    alias_url = ISO_ALIAS_TEMPLATE.format(release=release)
    iso_url = _resolve_iso_url(alias_url)
    return _UpstreamState(
        version=_derive_version(iso_url),
        iso_url=iso_url,
        iso_hash_sri=_prefetch_iso_hash(iso_url),
    )


def _replace_once(content: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, content, count=1, flags=re.MULTILINE)
    if count != 1:
        _fail(f"could not find unique {label} block in default.nix")

    return updated


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
    return _replace_once(
        updated,
        r'^    hash = ".*";$',
        f'    hash = "{upstream.iso_hash_sri}";',
        "src.hash",
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
        "--eval-page-url",
        default=DEFAULT_EVAL_PAGE_URL,
        help="Windows 11 Evaluation Center page URL to parse",
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

    upstream = _discover_upstream(args.eval_page_url)
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
