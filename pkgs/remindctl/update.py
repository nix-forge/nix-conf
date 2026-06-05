#!/usr/bin/env python3
"""Update ``remindctl`` from its latest stable GitHub release."""

from __future__ import annotations

import argparse
import contextlib
import difflib
import json
import os
import platform
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile
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


RELEASE_API_URL: Final = "https://api.github.com/repos/openclaw/remindctl/releases/latest"
EXPECTED_ASSET_NAME: Final = "remindctl-macos.zip"
EXPECTED_DOWNLOAD_HOST: Final = "github.com"
EXPECTED_DOWNLOAD_PATH: Final = re.compile(
    r"^/openclaw/remindctl/releases/download/v([^/]+)/remindctl-macos\.zip$"
)
EXPECTED_SKILL_HOST: Final = "raw.githubusercontent.com"
EXPECTED_SKILL_PATH: Final = re.compile(r"^/openclaw/remindctl/v([^/]+)/SKILL\.md$")
VERSION_PATTERN: Final = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")
HTTP_USER_AGENT: Final = "nix-conf-updater/1.0 (+https://github.com/NixOS/nixpkgs)"
MACHO_64_MAGIC: Final = b"\xcf\xfa\xed\xfe"
MACHO_HEADER_PREFIX_SIZE: Final = 8
CPU_TYPE_ARM64: Final = 0x0100000C


@dataclass(frozen=True)
class _UpstreamState:
    version: str
    url: str
    hash_sri: str
    agent_skill_content: str


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
        request = Request(
            url,
            headers={
                "Accept": "application/vnd.github+json",
                "User-Agent": HTTP_USER_AGENT,
                "X-GitHub-Api-Version": "2022-11-28",
            },
        )
        with urlopen(request, timeout=timeout, context=HTTPS_CONTEXT) as response:
            return json.load(response)
    except URLError as exc:
        _fail(f"failed to fetch {label} from {url}: {exc}")
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse JSON for {label} from {url}: {exc}")


def _fetch_text(url: str, *, label: str, timeout: int = 30) -> str:
    parsed_url = urlparse(url)
    if parsed_url.scheme != "https":
        _fail(f"unsupported URL scheme for {label}: {parsed_url.scheme!r}")

    try:
        request = Request(url, headers={"User-Agent": HTTP_USER_AGENT})
        with urlopen(request, timeout=timeout, context=HTTPS_CONTEXT) as response:
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


def _prefetch_hash(url: str, *, label: str) -> str:
    completed = _run_checked(
        [
            _get_binary("nix"),
            "store",
            "prefetch-file",
            "--json",
            "--hash-type",
            "sha256",
            url,
        ],
        error_message=f"failed to prefetch {label}",
    )

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


def _extract_asset_url(assets: object) -> str:
    if not isinstance(assets, list):
        _fail("latest release did not include an assets list")

    matches: list[str] = []
    for asset in assets:
        if not isinstance(asset, dict):
            continue
        asset_dict = cast("dict[str, object]", asset)
        if asset_dict.get("name") != EXPECTED_ASSET_NAME:
            continue
        url = asset_dict.get("browser_download_url")
        if isinstance(url, str):
            matches.append(url)

    if len(matches) != 1:
        _fail(
            f"expected exactly one {EXPECTED_ASSET_NAME!r} release asset, "
            f"found {len(matches)}",
        )

    return matches[0]


def _extract_release(data: object) -> tuple[str, str]:
    if not isinstance(data, dict):
        _fail("GitHub latest release response was not an object")

    release = cast("dict[str, object]", data)
    if release.get("draft") is not False or release.get("prerelease") is not False:
        _fail("GitHub latest release response was not a stable published release")

    tag_name = release.get("tag_name")
    if not isinstance(tag_name, str) or not tag_name.startswith("v"):
        _fail("latest release did not include a version tag beginning with `v`")

    version = tag_name.removeprefix("v")
    if VERSION_PATTERN.fullmatch(version) is None:
        _fail(f"latest release tag has an unexpected version format: {tag_name!r}")

    return version, _extract_asset_url(release.get("assets"))


def _validate_download_url(version: str, url: str) -> None:
    parsed_url = urlparse(url)
    if parsed_url.scheme != "https":
        _fail(f"remindctl download URL must use HTTPS: {url}")
    if parsed_url.netloc != EXPECTED_DOWNLOAD_HOST:
        _fail(f"unexpected remindctl download host: {parsed_url.netloc!r}")

    match = EXPECTED_DOWNLOAD_PATH.fullmatch(parsed_url.path)
    if match is None:
        _fail(f"unexpected remindctl archive path format: {parsed_url.path!r}")
    if match.group(1) != version:
        _fail(
            "remindctl release version does not match archive path version: "
            f"{version!r} != {match.group(1)!r}",
        )


def _agent_skill_url(version: str) -> str:
    return f"https://{EXPECTED_SKILL_HOST}/openclaw/remindctl/v{version}/SKILL.md"


def _validate_agent_skill_url(version: str, url: str) -> None:
    parsed_url = urlparse(url)
    if parsed_url.scheme != "https":
        _fail(f"remindctl agent skill URL must use HTTPS: {url}")
    if parsed_url.netloc != EXPECTED_SKILL_HOST:
        _fail(f"unexpected remindctl agent skill host: {parsed_url.netloc!r}")

    match = EXPECTED_SKILL_PATH.fullmatch(parsed_url.path)
    if match is None:
        _fail(f"unexpected remindctl agent skill path format: {parsed_url.path!r}")
    if match.group(1) != version:
        _fail(
            "remindctl release version does not match agent skill path version: "
            f"{version!r} != {match.group(1)!r}",
        )


def _validate_agent_skill(content: str) -> str:
    normalized = content.replace("\r\n", "\n")
    if not normalized.endswith("\n"):
        normalized += "\n"
    if not normalized.startswith("---\n"):
        _fail("remindctl agent skill is missing YAML frontmatter")
    if re.search(r"^name: apple-reminders$", normalized, flags=re.MULTILINE) is None:
        _fail("remindctl agent skill does not declare the expected name")
    return normalized


def _download_file(url: str, destination: Path, *, timeout: int = 60) -> None:
    try:
        request = Request(url, headers={"User-Agent": HTTP_USER_AGENT})
        with urlopen(request, timeout=timeout, context=HTTPS_CONTEXT) as response:
            destination.write_bytes(response.read())
    except URLError as exc:
        _fail(f"failed to download remindctl release archive from {url}: {exc}")


def _validate_arm64_macho(binary_path: Path) -> None:
    with binary_path.open("rb") as binary_file:
        header = binary_file.read(MACHO_HEADER_PREFIX_SIZE)

    if len(header) != MACHO_HEADER_PREFIX_SIZE or header[:4] != MACHO_64_MAGIC:
        _fail("remindctl release binary is not a thin little-endian 64-bit Mach-O")

    cpu_type = struct.unpack("<I", header[4:])[0]
    if cpu_type != CPU_TYPE_ARM64:
        _fail("remindctl release binary is not arm64")


def _validate_archive(version: str, url: str) -> None:
    if sys.platform != "darwin" or platform.machine() != "arm64":
        _fail("remindctl release validation requires an arm64 Darwin host")

    with tempfile.TemporaryDirectory(prefix="remindctl-release-") as temp_dir:
        temp_root = Path(temp_dir)
        archive_path = temp_root / EXPECTED_ASSET_NAME
        binary_path = temp_root / "remindctl"
        _download_file(url, archive_path)

        try:
            with zipfile.ZipFile(archive_path) as archive:
                members = [member for member in archive.infolist() if not member.is_dir()]
                if len(members) != 1 or members[0].filename != "remindctl":
                    _fail("remindctl release archive must contain only `remindctl`")
                binary_path.write_bytes(archive.read(members[0]))
        except zipfile.BadZipFile as exc:
            _fail(f"failed to read remindctl release archive: {exc}")

        _validate_arm64_macho(binary_path)
        binary_path.chmod(0o755)
        completed = _run_checked(
            [str(binary_path), "--version"],
            error_message="failed to run remindctl release binary",
        )
        reported_version = completed.stdout.strip()
        if reported_version != version:
            _fail(
                "remindctl release binary version does not match release tag: "
                f"{reported_version!r} != {version!r}",
            )


def _discover_upstream() -> _UpstreamState:
    version, url = _extract_release(
        _fetch_json(RELEASE_API_URL, label="remindctl latest GitHub release"),
    )
    _validate_download_url(version, url)
    _validate_archive(version, url)
    agent_skill_url = _agent_skill_url(version)
    _validate_agent_skill_url(version, agent_skill_url)
    return _UpstreamState(
        version=version,
        url=url,
        hash_sri=_prefetch_hash(url, label="release archive"),
        agent_skill_content=_validate_agent_skill(
            _fetch_text(agent_skill_url, label="remindctl agent skill"),
        ),
    )


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
    return parser.parse_args(list(argv))


def _main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    source_path = Path(__file__).with_name("source.nix")
    agent_skill_path = Path(__file__).with_name("SKILL.md")

    old_source_content = source_path.read_text(encoding="utf-8")
    old_agent_skill_content = agent_skill_path.read_text(encoding="utf-8")
    upstream = _discover_upstream()
    new_source_content = _render_source(upstream)
    new_agent_skill_content = upstream.agent_skill_content

    if (
        new_source_content == old_source_content
        and new_agent_skill_content == old_agent_skill_content
    ):
        _stdout("[update] remindctl is already up to date")
        return 0

    source_diff = _build_diff(old_source_content, new_source_content, source_path)
    agent_skill_diff = _build_diff(
        old_agent_skill_content,
        new_agent_skill_content,
        agent_skill_path,
    )
    sys.stdout.write(source_diff + agent_skill_diff)

    if args.check:
        return 1

    if args.dry_run:
        return 0

    _write_atomic(source_path, new_source_content)
    _write_atomic(agent_skill_path, new_agent_skill_content)
    _stdout("[update] updated remindctl")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
