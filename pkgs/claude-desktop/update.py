"""Update ``claude-desktop`` from Anthropic's macOS release feed."""

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
from typing import TYPE_CHECKING, Final, NoReturn, cast
from urllib.error import URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from pkgs.update_support import HTTPS_CONTEXT

if TYPE_CHECKING:
    from collections.abc import Sequence


RELEASES_URL: Final = (
    "https://downloads.claude.ai/releases/darwin/universal/RELEASES.json"
)
EXPECTED_HOST: Final = "downloads.claude.ai"
EXPECTED_PATH_PREFIX: Final = "/releases/darwin/universal/"
EXPECTED_ZIP_PATTERN: Final = re.compile(
    r"^/releases/darwin/universal/([^/]+)/Claude-([0-9a-f]+)\.zip$"
)
HTTP_USER_AGENT: Final = "nix-conf-updater/1.0 (+https://github.com/NixOS/nixpkgs)"
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

    try:
        request = Request(url, headers={"User-Agent": HTTP_USER_AGENT})
        with urlopen(request, timeout=timeout, context=HTTPS_CONTEXT) as response:
            return json.load(response)
    except URLError as exc:
        _fail(f"failed to fetch {label} from {url}: {exc}")
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse JSON for {label} from {url}: {exc}")


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
    if not re.fullmatch(r"sha256-[A-Za-z0-9+/=]+", hash_value):
        _fail(f"nix prefetch returned an unexpected hash format: {hash_value!r}")

    return hash_value


def _extract_latest_release(data: object) -> tuple[str, str]:
    if not isinstance(data, dict):
        _fail("Claude releases feed did not return an object")

    payload = cast("dict[str, object]", data)
    releases = payload.get("releases")
    if not isinstance(releases, list) or not releases:
        _fail("Claude releases feed did not include any releases")

    latest = releases[0]
    if not isinstance(latest, dict):
        _fail("latest Claude release entry is not an object")

    latest_release = cast("dict[str, object]", latest)
    update_to = latest_release.get("updateTo")
    if not isinstance(update_to, dict):
        _fail("latest Claude release is missing `updateTo` metadata")

    update_to_dict = cast("dict[str, object]", update_to)
    version = update_to_dict.get("version")
    url = update_to_dict.get("url")
    if not isinstance(version, str) or not version:
        _fail("latest Claude release is missing a string version")
    if not isinstance(url, str) or not url:
        _fail("latest Claude release is missing a string download URL")

    return version, url


def _validate_download_url(version: str, url: str) -> None:
    parsed_url = urlparse(url)
    if parsed_url.scheme != "https":
        _fail(f"Claude download URL must use HTTPS: {url}")
    if parsed_url.netloc != EXPECTED_HOST:
        _fail(f"unexpected Claude download host: {parsed_url.netloc!r}")
    if not parsed_url.path.startswith(EXPECTED_PATH_PREFIX):
        _fail(f"unexpected Claude download path: {parsed_url.path!r}")

    match = EXPECTED_ZIP_PATTERN.fullmatch(parsed_url.path)
    if match is None:
        _fail(f"unexpected Claude archive path format: {parsed_url.path!r}")

    version_from_path = match.group(1)
    if version_from_path != version:
        _fail(
            "Claude feed version does not match archive path version: "
            f"{version!r} != {version_from_path!r}",
        )


def _discover_release() -> _Release:
    version, url = _extract_latest_release(
        _fetch_json(RELEASES_URL, label="Claude releases feed"),
    )

    _validate_download_url(version, url)
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
    release = _discover_release()
    if not args.refresh and _source_matches_release(old_content, release):
        _stdout("[update] claude-desktop is already up to date")
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
    _stdout("[update] updated claude-desktop")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
