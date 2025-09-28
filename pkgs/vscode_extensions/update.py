#!/usr/bin/env python3
"""
Usage
-----
    python update.py --identifier <publisher>.<name> [--dry-run] [--verbose]

"""

from __future__ import annotations

import argparse
import dataclasses
import json
import os
import re
import subprocess
from functools import lru_cache
from pathlib import Path
from typing import Any, Callable, Iterable, List, Mapping, Optional, Tuple
import base64
import hashlib

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# ============================
# Configuration & Environment
# ============================


@dataclasses.dataclass(frozen=True)
class Env:
    """Configurable knobs via env vars with safe defaults.

    OVSVX_BASE      -  Base URL for Open VSX (default: https://open-vsx.org)
    GITHUB_TOKEN    - (optional) token for higher rate limits / private repos
    NIX_FLAKE       - flake ref used to evaluate vscode.version (default: nixpkgs)
    LOG_LEVEL       - debug|info|warn|error (default: info)
    FETCH_TIMEOUT   - per-request timeout seconds (default: 20)
    HTTP_RETRIES    - transient HTTP retry attempts (default: 3)
    """

    ovsx_base: str = os.environ.get("OVSVX_BASE", "https://open-vsx.org")
    github_token: Optional[str] = os.environ.get("GITHUB_TOKEN")
    nix_flake: str = os.environ.get("NIX_FLAKE", "nixpkgs")
    log_level: str = os.environ.get("LOG_LEVEL", "info").lower()
    fetch_timeout: int = int(os.environ.get("FETCH_TIMEOUT", "20"))
    http_retries: int = int(os.environ.get("HTTP_RETRIES", "3"))


# ============
# Simple logs
# ============
_LEVELS = {"debug": 10, "info": 20, "warn": 30, "error": 40}
HASH_CHUNK_SIZE = 2 * 1024 * 1024


def _lvl(env: Env) -> int:
    return _LEVELS.get(env.log_level, 20)


def log(env: Env, level: str, *parts: object) -> None:
    if _LEVELS[level] >= _lvl(env):
        # Structured-ish, single line
        msg = " ".join(str(p) for p in parts)
        print(f"[{level.upper()}] {msg}")


# ==================
# Small util helpers
# ==================
class UserError(RuntimeError):
    pass


class SysCmdError(RuntimeError):
    def __init__(self, cmd: List[str], code: int, out: str, err: str):
        super().__init__(f"Command failed ({code}): {' '.join(cmd)}\n{err or out}")
        self.cmd, self.code, self.out, self.err = cmd, code, out, err


def run(
    cmd: List[str], cwd: Optional[Path] = None, env: Optional[Mapping[str, str]] = None
) -> str:
    """Run a command and return stdout (stripped). Raises SysCmdError on failure."""
    proc = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        env={**os.environ, **(env or {})},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise SysCmdError(cmd, proc.returncode, proc.stdout, proc.stderr)
    return proc.stdout.strip()


def jget(obj: Mapping[str, Any], *keys: str, default: Any = None) -> Any:
    cur: Any = obj
    for k in keys:
        if not isinstance(cur, Mapping) or k not in cur:
            return default
        cur = cur[k]
    return cur


def parse_identifier(identifier: str) -> Tuple[str, str]:
    if "." not in identifier:
        raise UserError("--identifier must be of form <publisher>.<name>")
    pub, name = identifier.split(".", 1)
    if not pub or not name:
        raise UserError("Invalid identifier; missing publisher or name")
    return pub, name


# ==================================
# HTTP (requests) with retry/timeouts
# ==================================


def http_session(env: Env) -> requests.Session:
    sess = requests.Session()
    # Robust retry for transient errors
    retries = Retry(
        total=env.http_retries,
        backoff_factor=0.6,
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=("GET", "HEAD"),
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retries, pool_connections=10, pool_maxsize=20)
    sess.mount("http://", adapter)
    sess.mount("https://", adapter)
    if env.github_token:
        sess.headers["Authorization"] = f"Bearer {env.github_token}"
        sess.headers["X-GitHub-Api-Version"] = "2022-11-28"
    sess.headers.setdefault("Accept", "application/json")
    return sess


# =============================
# Open VSX: metadata & downloads
# =============================
@dataclasses.dataclass
class OvxVersion:
    version: str
    package_json_url: str
    vsix_url: str


def ovsx_latest_package_json_url(env: Env, publisher: str, name: str) -> str:
    base = env.ovsx_base.rstrip("/")
    return f"{base}/api/{publisher}/{name}/latest/file/package.json"


def ovsx_package_json_url(env: Env, publisher: str, name: str, version: str) -> str:
    base = env.ovsx_base.rstrip("/")
    return f"{base}/api/{publisher}/{name}/{version}/file/package.json"


def ovsx_vsix_url(env: Env, publisher: str, name: str, version: str) -> str:
    base = env.ovsx_base.rstrip("/")
    # canonical filename: <publisher>.<name>-<version>.vsix
    return f"{base}/api/{publisher}/{name}/{version}/file/{publisher}.{name}-{version}.vsix"


def ovsx_list_versions(
    env: Env, sess: requests.Session, publisher: str, name: str
) -> List[str]:
    """Return list of version strings (descending preferred if server returns so).

    Uses the documented JSON endpoints `/api/{namespace}/{extension}`.
    """
    base = env.ovsx_base.rstrip("/")
    url = f"{base}/api/{publisher}/{name}"
    r = sess.get(url, timeout=env.fetch_timeout)
    if r.status_code != 200:
        raise UserError(
            f"Open VSX metadata not found for {publisher}.{name} (HTTP {r.status_code})"
        )
    data = r.json()
    versions = [v.get("version") for v in data.get("versions", []) if v.get("version")]
    # Fallback: some instances put versions nested
    if not versions and isinstance(data, dict):
        for k in ("versions", "allVersions", "availableVersions"):
            vs = data.get(k)
            if isinstance(vs, list):
                versions = [
                    str(x.get("version"))
                    for x in vs
                    if isinstance(x, dict) and x.get("version")
                ]
                if versions:
                    break
    if not versions:
        # try latest only
        latest = data.get("version") or jget(data, "latestVersion")
        return [latest] if latest else []
    return versions


def ovsx_get_package_json(
    env: Env, sess: requests.Session, url: str
) -> Mapping[str, Any]:
    r = sess.get(url, timeout=env.fetch_timeout)
    if r.status_code != 200:
        raise UserError(f"Failed to fetch package.json ({r.status_code}) at {url}")
    try:
        return r.json()
    except json.JSONDecodeError as exc:
        snippet = r.text[:200].strip()
        raise UserError(
            f"Invalid JSON returned from Open VSX at {url}: {exc.msg}; got: {snippet}"
        ) from exc


# ====================
# VS Marketplace lookup
# ====================

MARKETPLACE_URL = (
    "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery"
)
MARKETPLACE_API_VERSION = "7.1-preview.1"


def _marketplace_target_rank(target: Optional[str]) -> int:
    if not target:
        return 1
    val = target.lower()
    if val in {"universal", "undefined"}:
        return 0
    if val in {"", "generic"}:
        return 1
    if val.startswith("linux") or val.startswith("alpine"):
        return 2
    if val.startswith("darwin"):
        return 3
    if val.startswith("win32"):
        return 4
    if val == "web":
        return 8
    return 6


def _marketplace_find_asset(ver: Mapping[str, Any], asset_type: str) -> Optional[str]:
    for file_info in ver.get("files", []) or []:
        if file_info.get("assetType") == asset_type and file_info.get("source"):
            return str(file_info["source"])
    return None


def _marketplace_fetch_manifest(
    env: Env, sess: requests.Session, url: Optional[str]
) -> Optional[Mapping[str, Any]]:
    if not url:
        return None
    r = sess.get(url, timeout=env.fetch_timeout)
    if r.status_code != 200:
        return None
    try:
        return r.json()
    except json.JSONDecodeError:
        return None


def _marketplace_properties(ver: Mapping[str, Any]) -> Mapping[str, str]:
    props: dict[str, str] = {}
    for prop in ver.get("properties", []) or []:
        key = prop.get("key")
        val = prop.get("value")
        if key and val is not None:
            props[str(key)] = str(val)
    return props


def _marketplace_is_prerelease(
    props: Mapping[str, str], manifest: Optional[Mapping[str, Any]] = None
) -> bool:
    if props.get("Microsoft.VisualStudio.Code.PreRelease", "").lower() == "true":
        return True
    if manifest and bool(manifest.get("preview")):
        return True
    return False


def choose_by_marketplace(
    env: Env,
    sess: requests.Session,
    publisher: str,
    name: str,
    vscode_version: Optional[str],
) -> Candidate:
    headers = {
        "Accept": f"application/json;api-version={MARKETPLACE_API_VERSION}",
        "Content-Type": "application/json",
        "User-Agent": "nix-conf-vscode-updater/1.0",
    }
    payload = {
        "filters": [
            {
                "criteria": [{"filterType": 7, "value": f"{publisher}.{name}"}],
                "pageNumber": 1,
                "pageSize": 40,
                "sortBy": 0,
                "sortOrder": 0,
            }
        ],
        # IncludeVersions (1) + IncludeFiles (2) + IncludeVersionProperties (16)
        # + ExcludeNonValidated (32) + IncludeAssetUri (64)
        "flags": 115,
    }
    r = sess.post(
        MARKETPLACE_URL,
        headers=headers,
        json=payload,
        timeout=env.fetch_timeout,
    )
    if r.status_code != 200:
        raise UserError(
            f"VS Marketplace lookup failed for {publisher}.{name} (HTTP {r.status_code})"
        )
    try:
        data = r.json()
    except json.JSONDecodeError as exc:
        raise UserError("VS Marketplace returned invalid JSON") from exc

    results = data.get("results") or []
    if not results:
        raise UserError(f"VS Marketplace returned no results for {publisher}.{name}")
    extensions = results[0].get("extensions") or []
    if not extensions:
        raise UserError(
            f"VS Marketplace returned no extension data for {publisher}.{name}"
        )

    versions: List[Mapping[str, Any]] = extensions[0].get("versions") or []
    if not versions:
        raise UserError(f"VS Marketplace listed no versions for {publisher}.{name}")

    grouped: dict[str, Tuple[int, Mapping[str, Any]]] = {}
    order: List[str] = []
    for idx, ver in enumerate(versions):
        ver_str = str(ver.get("version") or "").strip()
        if not ver_str:
            continue
        rank = _marketplace_target_rank(ver.get("targetPlatform"))
        existing = grouped.get(ver_str)
        if existing is None or rank < existing[0]:
            grouped[ver_str] = (rank, ver)
        if existing is None:
            order.append(ver_str)

    candidates: List[Tuple[bool, int, str, str]] = []

    for ver_str in order:
        rank, ver = grouped[ver_str]
        vsix_url = _marketplace_find_asset(
            ver, "Microsoft.VisualStudio.Services.VSIXPackage"
        )
        if not vsix_url:
            continue
        props = _marketplace_properties(ver)
        engine_spec = props.get("Microsoft.VisualStudio.Code.Engine")
        prerelease_known = "Microsoft.VisualStudio.Code.PreRelease" in props
        manifest_url = _marketplace_find_asset(
            ver, "Microsoft.VisualStudio.Code.Manifest"
        )

        need_manifest = manifest_url and (
            (engine_spec is None and vscode_version) or not prerelease_known
        )
        manifest: Optional[Mapping[str, Any]] = (
            _marketplace_fetch_manifest(env, sess, manifest_url)
            if need_manifest
            else None
        )
        if manifest and engine_spec is None:
            engine_spec = jget(manifest, "engines", "vscode")

        if (
            engine_spec
            and vscode_version
            and not engine_accepts(env, str(engine_spec), vscode_version)
        ):
            continue

        is_prerelease = _marketplace_is_prerelease(props, manifest)
        candidates.append((is_prerelease, rank, ver_str, vsix_url))

    if not candidates:
        raise UserError(
            f"Could not select a VS Marketplace version for {publisher}.{name}"
        )

    # Prefer stable entries first, then prereleases in original order.
    for is_prerelease in (False, True):
        for cand in candidates:
            cand_is_pre, rank, ver_str, vsix_url = cand
            if cand_is_pre != is_prerelease:
                continue
            return Candidate(version=ver_str, vsix_url=vsix_url)

    raise UserError(f"Could not select a VS Marketplace version for {publisher}.{name}")


# ====================
# GitHub: latest tags
# ====================
@dataclasses.dataclass
class GhLatest:
    tag: str
    vsix_asset_url: Optional[str]


def parse_github_repo_url(repo_url: str) -> Optional[Tuple[str, str]]:
    m = re.search(r"github\.com/([^/]+)/([^/#?]+)", repo_url)
    if not m:
        return None
    owner, repo = m.group(1), m.group(2).removesuffix(".git")
    return owner, repo


def github_latest_release(
    env: Env, sess: requests.Session, owner: str, repo: str
) -> GhLatest:
    url = f"https://api.github.com/repos/{owner}/{repo}/releases/latest"
    r = sess.get(url, timeout=env.fetch_timeout)
    if r.status_code != 200:
        raise UserError(
            f"GitHub latest release lookup failed for {owner}/{repo} (HTTP {r.status_code})"
        )
    data = r.json()
    tag = str(data.get("tag_name") or data.get("name") or "").lstrip("v").strip()
    vsix_url: Optional[str] = None
    for asset in data.get("assets", []) or []:
        name = str(asset.get("name") or "")
        if name.endswith(".vsix"):
            vsix_url = asset.get("browser_download_url")
            break
    return GhLatest(tag=tag, vsix_asset_url=vsix_url)


# =====================================
# Nix helpers: version, prefetch hashing
# =====================================


def nix_vscode_version(env: Env) -> Optional[str]:
    """Return the VS Code version from the target flake (nixpkgs by default)."""
    try:
        return run(["nix", "eval", "--raw", f"{env.nix_flake}#vscode.version"]) or None
    except Exception:
        return None


def _stream_sha256(env: Env, sess: requests.Session, url: str) -> bytes:
    try:
        with sess.get(url, stream=True, timeout=env.fetch_timeout) as resp:
            if resp.status_code != 200:
                raise UserError(f"Failed to download {url} (HTTP {resp.status_code})")
            hasher = hashlib.sha256()
            for chunk in resp.iter_content(chunk_size=HASH_CHUNK_SIZE):
                if chunk:
                    hasher.update(chunk)
    except UserError:
        raise
    except Exception as exc:
        raise UserError(f"Failed to download {url}: {exc}") from exc
    return hasher.digest()


def _digest_to_sri(digest: bytes) -> str:
    return "sha256-" + base64.b64encode(digest).decode("ascii")


def compute_vsix_sri(env: Env, sess: requests.Session, url: str) -> str:
    digest = _stream_sha256(env, sess, url)
    return _digest_to_sri(digest)


# =====================================
# Nix file update (default.nix in package)
# =====================================
@dataclasses.dataclass
class DerivationUpdate:
    file: Path
    old_version: Optional[str]
    new_version: str
    old_hash: Optional[str]
    new_hash: str


def find_default_nix_for_identifier(env: Env, publisher: str, name: str) -> Path:
    """Search pkgs/vscode_extensions/**/default.nix and return the matching file.
    Match if the file contains publisher/name matching the identifier.
    """
    base = Path(__file__).resolve().parent
    # Script is under pkgs/vscode_extensions/update.py -> search siblings
    search_root = base
    candidates = list(search_root.glob("*/default.nix"))
    if not candidates:
        raise UserError(f"No default.nix files found under {search_root}")

    for f in candidates:
        try:
            text = f.read_text(encoding="utf-8")
        except Exception:
            continue
        # Accept any of these patterns to identify the target package
        if (
            re.search(rf"\bpublisher\s*=\s*\"{re.escape(publisher)}\"\s*;", text)
            and re.search(rf"\bname\s*=\s*\"{re.escape(name)}\"\s*;", text)
        ) or re.search(
            rf"\bidentifier\s*=\s*\"{re.escape(publisher)}\.{re.escape(name)}\"\s*;",
            text,
        ):
            return f
    raise UserError(f"Could not find a package default.nix for {publisher}.{name}")


def update_default_nix(
    env: Env, file: Path, new_version: str, new_hash_sri: str
) -> DerivationUpdate:
    text = file.read_text(encoding="utf-8")

    def sub1(pattern: str, repl: str) -> Tuple[str, Optional[str]]:
        m = re.search(pattern, text, flags=re.MULTILINE)
        if not m:
            return text, None
        old = m.group(1)
        return re.sub(pattern, repl, text, count=1, flags=re.MULTILINE), old

    # Replace version = "...";
    new_text, old_version = sub1(
        r"version\s*=\s*\"([^\"]+)\"\s*;", f'version = "{new_version}";'
    )
    if new_text == text:
        # Some derivations use `pname`/`version` differently, attempt pnameVersion
        new_text, old_version = sub1(
            r"\bversion\s*=\s*\"([^\"]+)\"\s*;", f'version = "{new_version}";'
        )
    text = new_text

    # Replace hash or sha256 (use whichever the file has)
    new_text_h, old_hash = sub1(
        r"hash\s*=\s*\"([^\"]+)\"\s*;", f'hash = "{new_hash_sri}";'
    )
    text = new_text_h
    if new_text_h == text:  # unchanged -> try sha256
        new_text_s, old_hash = sub1(
            r"sha256\s*=\s*\"([^\"]+)\"\s*;", f'sha256 = "{new_hash_sri}";'
        )
        text = new_text_s

    if new_version and new_hash_sri not in text:
        # If neither pattern matched, try simple url fetcher style (fetchurl { sha256 = ...; })
        replacement = f"\\1{new_hash_sri}\\3"
        text = re.sub(
            r'(sha256\s*=\s*")([^"]+)("\s*;)',
            replacement,
            text,
            count=1,
        )

    if old_version is None:
        log(
            env,
            "warn",
            f"Could not locate existing version in {file}; attempted blind hash replacement",
        )

    file.write_text(text, encoding="utf-8")
    return DerivationUpdate(
        file=file,
        old_version=old_version,
        new_version=new_version,
        old_hash=old_hash,
        new_hash=new_hash_sri,
    )


def current_version_and_hash(file: Path) -> Tuple[Optional[str], Optional[str]]:
    try:
        text = file.read_text(encoding="utf-8")
    except Exception:
        return None, None
    version_match = re.search(r"version\s*=\s*\"([^\"]+)\"\s*;", text)
    hash_match = re.search(r"(?:hash|sha256)\s*=\s*\"([^\"]+)\"\s*;", text)
    version = version_match.group(1) if version_match else None
    hash_value = hash_match.group(1) if hash_match else None
    return version, hash_value


# ==============================
# Version/compatibility helpers
# ==============================


def normalize_vscode_version(v: str) -> str:
    # VS Code sometimes adds labels; we only need semver core
    match = re.match(r"\d+\.\d+\.\d+", v)
    return match.group(0) if match else v


@dataclasses.dataclass(frozen=True, order=True)
class SimpleVersion:
    major: int
    minor: int
    patch: int

    @classmethod
    def parse(cls, text: str) -> Optional["SimpleVersion"]:
        text = text.strip()
        m = re.search(r"(\d+)(?:\.(\d+))?(?:\.(\d+))?", text)
        if not m:
            return None
        return cls(int(m.group(1)), int(m.group(2) or 0), int(m.group(3) or 0))


def _version_from_parts(parts: Iterable[int]) -> SimpleVersion:
    values = list(parts)
    filled = (values + [0, 0, 0])[:3]
    return SimpleVersion(filled[0], filled[1], filled[2])


def _parse_partial_range(
    text: str,
) -> Tuple[Optional[SimpleVersion], Optional[SimpleVersion], bool]:
    raw = text.strip().lstrip("vV")
    if not raw or raw in {"*", "x", "X"}:
        return None, None, False
    segments = [seg.strip() for seg in raw.replace("*", "x").split(".")]
    numeric: List[int] = []
    wildcard_idx: Optional[int] = None
    for idx, seg in enumerate(segments):
        if not seg or seg.lower() == "x":
            wildcard_idx = idx
            break
        match = re.match(r"(\d+)", seg)
        if not match:
            wildcard_idx = idx
            break
        numeric.append(int(match.group(1)))

    if wildcard_idx is None and len(numeric) < len(segments):
        wildcard_idx = len(numeric)
    if wildcard_idx is None and len(numeric) < 3:
        wildcard_idx = len(numeric)

    lower = _version_from_parts(numeric)
    exact = wildcard_idx is None and len(numeric) >= 3
    if exact:
        return lower, lower, True

    if wildcard_idx == 0:
        # Fully wildcarded (e.g. "x") -> any version
        return None, None, False

    upper_nums = [lower.major, lower.minor, lower.patch]
    upper_index = (wildcard_idx or len(numeric)) - 1
    if upper_index <= 0:
        upper_nums[0] += 1
        upper_nums[1] = 0
        upper_nums[2] = 0
    elif upper_index == 1:
        upper_nums[1] += 1
        upper_nums[2] = 0
    else:
        upper_nums[2] += 1
    upper = SimpleVersion(upper_nums[0], upper_nums[1], upper_nums[2])
    return lower, upper, False


def _caret_upper_bound(base: SimpleVersion) -> SimpleVersion:
    if base.major > 0:
        return SimpleVersion(base.major + 1, 0, 0)
    if base.minor > 0:
        return SimpleVersion(0, base.minor + 1, 0)
    return SimpleVersion(0, 0, base.patch + 1)


def _tilde_upper_bound(base: SimpleVersion, source: str) -> SimpleVersion:
    cleaned = source.strip().lstrip("vV")
    segments = [seg for seg in cleaned.split(".") if seg]
    if len(segments) <= 1:
        return SimpleVersion(base.major + 1, 0, 0)
    return SimpleVersion(base.major, base.minor + 1, 0)


Comparator = Callable[[SimpleVersion], bool]


def _cmp_ge(threshold: SimpleVersion) -> Comparator:
    def _inner(value: SimpleVersion) -> bool:
        return value >= threshold

    return _inner


def _cmp_gt(threshold: SimpleVersion) -> Comparator:
    def _inner(value: SimpleVersion) -> bool:
        return value > threshold

    return _inner


def _cmp_le(threshold: SimpleVersion) -> Comparator:
    def _inner(value: SimpleVersion) -> bool:
        return value <= threshold

    return _inner


def _cmp_lt(threshold: SimpleVersion) -> Comparator:
    def _inner(value: SimpleVersion) -> bool:
        return value < threshold

    return _inner


def _cmp_eq(target: SimpleVersion) -> Comparator:
    def _inner(value: SimpleVersion) -> bool:
        return value == target

    return _inner


def _expand_token(token: str) -> List[Comparator]:
    token = token.strip()
    if not token or token in {"*", "x", "X"}:
        return []
    if token.startswith("^"):
        base = SimpleVersion.parse(token[1:])
        if not base:
            return []
        upper_bound = _caret_upper_bound(base)
        return [_cmp_ge(base), _cmp_lt(upper_bound)]
    if token.startswith("~"):
        raw = token[1:]
        base = SimpleVersion.parse(raw)
        if not base:
            return []
        upper_bound = _tilde_upper_bound(base, raw)
        return [_cmp_ge(base), _cmp_lt(upper_bound)]

    op = None
    for prefix in (">=", "<=", ">", "<", "="):
        if token.startswith(prefix):
            op = prefix
            token = token[len(prefix) :]
            break
    rest = token.strip()
    if not rest or rest in {"*", "x", "X"}:
        return []

    lower, upper, exact = _parse_partial_range(rest)
    comparators: List[Comparator] = []

    if op in (None, "="):
        if lower is None and upper is None:
            return []
        if exact and lower is not None:
            comparators.append(_cmp_eq(lower))
            return comparators
        if lower is not None:
            comparators.append(_cmp_ge(lower))
        if upper is not None:
            comparators.append(_cmp_lt(upper))
        return comparators

    if lower is None:
        return []
    if op == ">=":
        comparators.append(_cmp_ge(lower))
    elif op == ">":
        comparators.append(_cmp_gt(lower))
    elif op == "<=":
        comparators.append(_cmp_le(lower))
    elif op == "<":
        comparators.append(_cmp_lt(lower))
    return comparators


@lru_cache(maxsize=512)
def _compile_range(expr: str) -> Tuple[Comparator, ...]:
    expr = expr.strip()
    if not expr:
        return tuple()
    hyphen = re.match(r"^([^\s]+)\s*-\s*([^\s]+)$", expr)
    if hyphen:
        lower = SimpleVersion.parse(hyphen.group(1))
        upper = SimpleVersion.parse(hyphen.group(2))
        comps: List[Comparator] = []
        if lower:
            comps.append(_cmp_ge(lower))
        if upper:
            comps.append(_cmp_le(upper))
        return tuple(comps)

    comparators: List[Comparator] = []
    for token in re.split(r"\s+", expr):
        if token:
            comparators.extend(_expand_token(token))
    return tuple(comparators)


@lru_cache(maxsize=256)
def _compile_spec(spec: str) -> Tuple[Tuple[Comparator, ...], ...]:
    normalized = (spec or "").strip()
    if not normalized or normalized in {"*", "latest"}:
        return (tuple(),)
    compiled: List[Tuple[Comparator, ...]] = []
    for part in normalized.split("||"):
        rng = _compile_range(part)
        if rng:
            compiled.append(rng)
    return tuple(compiled) if compiled else (tuple(),)


def npm_spec_accepts(spec: str, version: SimpleVersion) -> bool:
    for comparators in _compile_spec(spec):
        if not comparators:
            return True
        if all(comp(version) for comp in comparators):
            return True
    return False


def engine_accepts(env: Env, engine_spec: str, vscode_version: str) -> bool:
    try:
        parsed_version = SimpleVersion.parse(normalize_vscode_version(vscode_version))
        if not parsed_version:
            return True
        return npm_spec_accepts(engine_spec, parsed_version)
    except Exception:
        # Be permissive if parsing fails
        return True


# =================
# Update strategies
# =================
@dataclasses.dataclass
class Candidate:
    version: str
    vsix_url: str


def choose_by_github(
    env: Env, sess: requests.Session, publisher: str, name: str
) -> Optional[Candidate]:
    # Discover repo from latest package.json on Open VSX
    pkg_url = ovsx_latest_package_json_url(env, publisher, name)
    try:
        pkg = ovsx_get_package_json(env, sess, pkg_url)
    except UserError as exc:
        log(env, "debug", f"Open VSX metadata unavailable for GitHub lookup: {exc}")
        return None

    repo_url = jget(pkg, "repository")
    if isinstance(repo_url, Mapping):
        repo_url = str(repo_url.get("url", ""))
    elif not isinstance(repo_url, str):
        repo_url = ""

    gh = None
    if repo_url and "github.com" in repo_url:
        parsed = parse_github_repo_url(repo_url)
        if parsed:
            owner, repo = parsed
            gh = github_latest_release(env, sess, owner, repo)
    if not gh:
        return None

    # Prefer GH .vsix asset when present
    if gh.vsix_asset_url:
        return Candidate(version=gh.tag, vsix_url=gh.vsix_asset_url)

    # Otherwise, attempt to fetch from Open VSX for that tag
    vsix_url = ovsx_vsix_url(env, publisher, name, gh.tag)
    # HEAD to confirm existence (faster)
    r = sess.head(vsix_url, timeout=env.fetch_timeout)
    if r.status_code == 200:
        return Candidate(version=gh.tag, vsix_url=vsix_url)

    # Could not satisfy via GH -> give up to caller
    return None


def choose_by_open_vsx(
    env: Env,
    sess: requests.Session,
    publisher: str,
    name: str,
    vscode_version: Optional[str],
) -> Candidate:
    versions = ovsx_list_versions(env, sess, publisher, name)
    if not versions:
        # As a last resort, try "latest"
        pkg_url = ovsx_latest_package_json_url(env, publisher, name)
        pkg = ovsx_get_package_json(env, sess, pkg_url)
        v = str(pkg.get("version")) if pkg.get("version") else None
        if not v:
            raise UserError(f"No versions listed for {publisher}.{name}")
        versions = [v]

    # Iterate newest -> oldest, find the first compatible one
    for ver in versions:
        pkg_url = ovsx_package_json_url(env, publisher, name, ver)
        try:
            pkg = ovsx_get_package_json(env, sess, pkg_url)
        except UserError:
            continue
        engine = jget(pkg, "engines", "vscode") or jget(
            pkg, "engines", "vscode-insiders"
        )
        if vscode_version:
            if engine and not engine_accepts(env, str(engine), vscode_version):
                # Not compatible with target VS Code, continue
                continue
        vsix_url = ovsx_vsix_url(env, publisher, name, ver)
        # HEAD to confirm
        r = sess.head(vsix_url, timeout=env.fetch_timeout)
        if r.status_code == 200:
            return Candidate(version=ver, vsix_url=vsix_url)

    raise UserError(f"Could not find a compatible version for {publisher}.{name}")


# =====
# Main
# =====


def main(argv: Optional[List[str]] = None) -> int:
    env = Env()
    ap = argparse.ArgumentParser(
        description="Update a VS Code extension default.nix derivation"
    )
    ap.add_argument("--identifier", required=True, help="<publisher>.<name>")
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="Do not write any files; just print actions",
    )
    ap.add_argument(
        "--verbose", action="store_true", help="Force LOG_LEVEL=debug for this run"
    )
    args = ap.parse_args(argv)

    if args.verbose:
        env2 = dataclasses.replace(env, log_level="debug")
        env = env2

    pub, name = parse_identifier(args.identifier)
    sess = http_session(env)
    vscode_version = nix_vscode_version(env)
    if vscode_version:
        log(env, "debug", f"Detected VS Code version {vscode_version}")

    # Locate target derivation file
    deriv_file = find_default_nix_for_identifier(env, pub, name)
    log(env, "info", f"Matched {pub}.{name} -> {deriv_file}")
    current_version, current_hash = current_version_and_hash(deriv_file)
    if current_version:
        log(env, "debug", f"Existing version {current_version}")

    # Strategy 1: GitHub preferred (if listed in metadata)
    cand: Optional[Candidate] = None
    try:
        cand = choose_by_github(env, sess, pub, name)
        if cand:
            log(env, "info", f"Chose GitHub latest version {cand.version}")
    except UserError as e:
        log(env, "debug", f"GitHub path not applicable: {e}")

    # Strategy 2: Open VSX latest compatible
    if not cand:
        try:
            cand = choose_by_open_vsx(env, sess, pub, name, vscode_version)
            if cand:
                log(env, "info", f"Chose Open VSX version {cand.version}")
        except UserError as e:
            log(env, "debug", f"Open VSX path not applicable: {e}")

    # Strategy 3: VS Marketplace (for extensions not on Open VSX)
    if not cand:
        cand = choose_by_marketplace(env, sess, pub, name, vscode_version)
        log(env, "info", f"Chose Marketplace version {cand.version}")

    # Prefetch to get SRI hash
    if current_version == cand.version and current_hash:
        log(env, "info", f"{pub}.{name} already at {cand.version}; skipping download")
        sri = current_hash
    else:
        log(env, "info", f"Prefetching {cand.vsix_url}")
        sri = compute_vsix_sri(env, sess, cand.vsix_url)
        log(env, "debug", f"SRI hash: {sri}")

    if args.dry_run:
        print(
            json.dumps(
                {
                    "identifier": f"{pub}.{name}",
                    "version": cand.version,
                    "vsix_url": cand.vsix_url,
                    "hash": sri,
                    "derivation": str(deriv_file),
                },
                indent=2,
            )
        )
        return 0

    if current_version == cand.version and current_hash == sri:
        log(env, "info", f"{pub}.{name} already up-to-date; nothing to change")
        return 0

    # Update default.nix in place
    upd = update_default_nix(env, deriv_file, cand.version, sri)
    log(
        env,
        "info",
        f"Updated {upd.file}: version {upd.old_version} -> {upd.new_version}",
    )
    if upd.old_hash:
        log(env, "debug", f"Replaced hash: {upd.old_hash} -> {upd.new_hash}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
