"""Update the pinned SpotX-supported Spotify macOS package."""

from __future__ import annotations

import argparse
import base64
import difflib
import json
import re
import subprocess
import sys
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


HTTP_USER_AGENT: Final = "nix-conf-updater/1.0 (+https://github.com/NixOS/nixpkgs)"
REPO_OWNER: Final = "SpotX-Official"
REPO_NAME: Final = "SpotX-Bash"
DEFAULT_REF: Final = "main"
SPOTIFY_DOWNLOAD_HOST: Final = "upgrade.scdn.co"
GITHUB_RAW_HOST: Final = "raw.githubusercontent.com"


@dataclass(frozen=True)
class _SpotifySource:
    version: str
    build: str
    build_id: str
    url: str
    hash: str


@dataclass(frozen=True)
class _SpotxSource:
    rev: str
    hash: str


@dataclass(frozen=True)
class _SourceState:
    spotify: _SpotifySource
    spotx: _SpotxSource


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
    if parsed_url.netloc != GITHUB_RAW_HOST:
        _fail(f"unexpected host for {label}: {parsed_url.netloc!r}")

    try:
        request = Request(url, headers={"User-Agent": HTTP_USER_AGENT})
        with urlopen(request, timeout=timeout, context=HTTPS_CONTEXT) as response:
            return response.read().decode("utf-8")
    except URLError as exc:
        _fail(f"failed to fetch {label} from {url}: {exc}")
    except UnicodeDecodeError as exc:
        _fail(f"failed to decode {label} from {url}: {exc}")


def _run_checked(args: list[str], *, error_message: str) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(args, capture_output=True, check=False, text=True)
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "(no output)"
        _fail(f"{error_message}:\n{detail}")
    return completed


def _prefetch_hash(url: str, *, unpack: bool = False, name: str | None = None) -> str:
    parsed_url = urlparse(url)
    if parsed_url.scheme != "https":
        _fail(f"unsupported prefetch URL scheme: {parsed_url.scheme!r}")
    if parsed_url.netloc not in {SPOTIFY_DOWNLOAD_HOST, "github.com"}:
        _fail(f"unexpected prefetch host: {parsed_url.netloc!r}")

    command = [
        "nix",
        "store",
        "prefetch-file",
        "--json",
        "--hash-type",
        "sha256",
    ]
    if unpack:
        command.append("--unpack")
    if name is not None:
        command.extend(["--name", name])
    command.append(url)

    completed = _run_checked(command, error_message=f"failed to prefetch {url}")

    try:
        data = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse nix prefetch JSON output: {exc}")

    hash_value = data.get("hash")
    if not isinstance(hash_value, str):
        _fail("nix prefetch JSON did not include a string `hash` field")
    return hash_value


def _latest_rev(ref: str) -> str:
    output = _run_checked(
        ["git", "ls-remote", f"https://github.com/{REPO_OWNER}/{REPO_NAME}.git", ref],
        error_message=f"failed to resolve SpotX-Bash ref {ref}",
    ).stdout.strip()
    if not output:
        _fail(f"SpotX-Bash ref {ref} did not resolve")
    rev = output.split()[0]
    if not re.fullmatch(r"[0-9a-f]{40}", rev):
        _fail(f"SpotX-Bash ref {ref} resolved to unexpected revision {rev!r}")
    return rev


def _shell_string_variable(script: str, name: str) -> str:
    lines = script.splitlines()
    start = next(
        (
            index
            for index, line in enumerate(lines)
            if line.startswith(f'{name}=$(printf "%s" \\')
        ),
        None,
    )
    if start is None:
        _fail(f"could not find SpotX variable {name}")

    block: list[str] = []
    for line in lines[start + 1 :]:
        block.append(line)
        if line.rstrip().endswith(")"):
            break
    else:
        _fail(f"SpotX variable {name} did not terminate as expected")

    parts = re.findall(r'"([^"]*)"', "\n".join(block))
    if not parts:
        _fail(f"SpotX variable {name} did not contain string parts")
    return "".join(parts)


def _base64_template_variable(script: str, name: str) -> str:
    lines = script.splitlines()
    start = next(
        (
            index
            for index, line in enumerate(lines)
            if re.match(rf"\s*(?:local\s+)?{re.escape(name)}=\$\(printf", line)
        ),
        None,
    )
    if start is None:
        _fail(f"could not find SpotX template {name}")

    block: list[str] = []
    for line in lines[start + 1 :]:
        block.append(line)
        if "| rev | base64 --decode | base64 --decode" in line:
            break
    else:
        _fail(f"SpotX template {name} did not terminate as expected")

    parts = re.findall(r'"([^"]*)"', "\n".join(block))
    if not parts:
        _fail(f"SpotX template {name} did not contain string parts")

    try:
        first = base64.b64decode("".join(parts)[::-1])
        second = base64.b64decode(first)
    except ValueError as exc:
        _fail(f"failed to decode SpotX template {name}: {exc}")
    return second.decode("utf-8")


def _literal_variable(script: str, name: str) -> str:
    match = re.search(rf'^{re.escape(name)}="([^"]+)"$', script, re.MULTILINE)
    if match is None:
        _fail(f"could not find SpotX variable {name}")
    return match.group(1)


def _spotify_fauth(script: str) -> str:
    fauth_suffix = _shell_string_variable(script, "latestA_A")
    fauth_header_match = re.search(
        r"fauth=([^$]+)\.\$\{tbzFauth\}",
        _base64_template_variable(script, "tbzTpl"),
    )
    if fauth_header_match is None:
        _fail("could not extract Spotify fauth header from SpotX template")
    return f"{fauth_header_match.group(1)}.{fauth_suffix}"


def _discover_spotify_source(script: str) -> _SpotifySource:
    build = _literal_variable(script, "buildVer")
    version = re.sub(r"\.g[0-9a-f]+$", "", build)
    build_id = _literal_variable(script, "latestB_A")
    url = (
        "https://upgrade.scdn.co/upgrade/client/osx-arm64/"
        f"spotify-autoupdate-{build}-{build_id}.tbz?fauth={_spotify_fauth(script)}"
    )
    return _SpotifySource(
        version=version,
        build=build,
        build_id=build_id,
        url=url,
        hash=_prefetch_hash(
            url,
            name=f"spotify-autoupdate-{build}-{build_id}.tbz",
        ),
    )


def _discover_source(ref: str) -> _SourceState:
    spotx_rev = _latest_rev(ref)
    script_url = f"https://raw.githubusercontent.com/{REPO_OWNER}/{REPO_NAME}/{spotx_rev}/spotx.sh"
    script = _fetch_text(script_url, label="SpotX-Bash spotx.sh")
    archive_url = f"https://github.com/{REPO_OWNER}/{REPO_NAME}/archive/{spotx_rev}.tar.gz"
    return _SourceState(
        spotify=_discover_spotify_source(script),
        spotx=_SpotxSource(
            rev=spotx_rev,
            hash=_prefetch_hash(
                archive_url,
                unpack=True,
                name=f"{REPO_NAME}-{spotx_rev}.tar.gz",
            ),
        ),
    )


def _render_source(source: _SourceState) -> str:
    return (
        "{\n"
        f'  version = "{source.spotify.version}";\n'
        "  spotify = {\n"
        f'    build = "{source.spotify.build}";\n'
        f'    buildId = "{source.spotify.build_id}";\n'
        '    arch = "osx-arm64";\n'
        f'    url = "{source.spotify.url}";\n'
        f'    hash = "{source.spotify.hash}";\n'
        "  };\n"
        "  spotx = {\n"
        f'    owner = "{REPO_OWNER}";\n'
        f'    repo = "{REPO_NAME}";\n'
        f'    rev = "{source.spotx.rev}";\n'
        f'    hash = "{source.spotx.hash}";\n'
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
        )
    )


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="print diff but do not write")
    parser.add_argument("--check", action="store_true", help="exit non-zero when updates are available")
    parser.add_argument("--ref", default=DEFAULT_REF, help="SpotX-Bash git ref to pin")
    return parser.parse_args(list(argv))


def _main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    source_path = Path(__file__).with_name("source.nix")
    source = _discover_source(args.ref)
    new_content = _render_source(source)
    old_content = source_path.read_text(encoding="utf-8")
    if new_content == old_content:
        _stdout(f"[update] spotify-spotx {source.spotify.version} is already up to date")
        return 0

    diff_text = _build_diff(old_content, new_content, source_path)
    if diff_text:
        sys.stdout.write(diff_text)

    if args.check:
        return 1
    if args.dry_run:
        return 0

    _write_atomic(source_path, new_content)
    _stdout(f"[update] updated spotify-spotx to {source.spotify.version} ({source.spotx.rev})")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
