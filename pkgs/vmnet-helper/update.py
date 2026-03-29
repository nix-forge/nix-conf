"""Update ``vmnet-helper`` source pins from the latest GitHub release."""

from __future__ import annotations

import argparse
import contextlib
import difflib
import json
import os
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

if TYPE_CHECKING:
    from collections.abc import Sequence


REPO_API_URL: Final = "https://api.github.com/repos/nirs/vmnet-helper/releases/latest"
ARCHIVE_URL_TEMPLATE: Final = (
    "https://github.com/nirs/vmnet-helper/archive/{tag}.tar.gz"
)
HTTP_USER_AGENT: Final = "nix-conf-updater/1.0 (+https://github.com/NixOS/nixpkgs)"


@dataclass(frozen=True)
class _UpstreamState:
    version: str
    rev: str
    hash_sri: str


def _stdout(message: str) -> None:
    sys.stdout.write(f"{message}\n")


def _stderr(message: str) -> None:
    sys.stderr.write(f"{message}\n")


def _fail(message: str) -> NoReturn:
    _stderr(f"error: {message}")
    raise SystemExit(1)


def _fetch_json(url: str, *, label: str, timeout: int = 30) -> dict[str, object]:
    parsed_url = urlparse(url)
    if parsed_url.scheme != "https":
        _fail(f"unsupported URL scheme for {label}: {parsed_url.scheme!r}")

    try:
        request = Request(url, headers={"User-Agent": HTTP_USER_AGENT})
        with urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except URLError as exc:
        _fail(f"failed to fetch {label} from {url}: {exc}")
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse JSON for {label}: {exc}")

    if not isinstance(payload, dict):
        _fail(f"unexpected JSON shape for {label}: expected object")
    return payload


def _get_nix_binary() -> str:
    nix_binary = shutil.which("nix")
    if isinstance(nix_binary, str):
        return nix_binary
    _fail("`nix` executable not found in PATH")


def _prefetch_hash(url: str) -> str:
    completed = subprocess.run(
        [
            _get_nix_binary(),
            "store",
            "prefetch-file",
            "--json",
            "--unpack",
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
        _fail(f"failed to prefetch source hash:\n{detail}")

    try:
        data = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse nix prefetch JSON output: {exc}")

    hash_value = data.get("hash")
    if not isinstance(hash_value, str):
        _fail("nix prefetch JSON did not include a string `hash` field")
    return hash_value


def _discover_upstream() -> _UpstreamState:
    payload = _fetch_json(REPO_API_URL, label="vmnet-helper latest release")
    tag_name = payload.get("tag_name")
    if not isinstance(tag_name, str) or not tag_name:
        _fail("release payload did not include tag_name")

    version = tag_name[1:] if tag_name.startswith("v") else tag_name
    url = ARCHIVE_URL_TEMPLATE.format(tag=tag_name)
    return _UpstreamState(version=version, rev=tag_name, hash_sri=_prefetch_hash(url))


def _render_source(upstream: _UpstreamState) -> str:
    return (
        "{\n"
        f'  version = "{upstream.version}";\n'
        "  src = {\n"
        '    owner = "nirs";\n'
        '    repo = "vmnet-helper";\n'
        f'    rev = "{upstream.rev}";\n'
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
        "--dry-run", action="store_true", help="print diff but do not write"
    )
    parser.add_argument(
        "--check", action="store_true", help="exit non-zero when updates are available"
    )
    return parser.parse_args(list(argv))


def _main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    source_path = Path(__file__).with_name("source.nix")

    old_content = source_path.read_text(encoding="utf-8")
    new_content = _render_source(_discover_upstream())

    if new_content == old_content:
        _stdout("[update] vmnet-helper is already up to date")
        return 0

    diff_text = _build_diff(old_content, new_content, source_path)
    if diff_text:
        sys.stdout.write(diff_text)

    if args.check:
        return 1
    if args.dry_run:
        return 0

    _write_atomic(source_path, new_content)
    _stdout("[update] updated vmnet-helper")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
