#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import urllib.request
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

# ---------- logging ----------
LOG_LEVEL = os.environ.get("LOG_LEVEL", "info").lower()
LEVELS = {"error": 0, "warn": 1, "info": 2, "debug": 3}


def _lvl_num(name: str) -> int:
    return LEVELS.get(name, 2)


def _cfg_lvl() -> int:
    return _lvl_num(LOG_LEVEL)


def _ts() -> str:
    # Use timezone-aware UTC; be compatible with Python < 3.11
    try:
        tz = dt.timezone.utc  # type: ignore[attr-defined]
    except Exception:
        tz = None
    now = dt.datetime.now(tz) if tz else dt.datetime.utcnow()
    return now.strftime("%Y-%m-%dT%H:%M:%SZ")


def log(level: str, *parts: str) -> None:
    if _lvl_num(level) <= _cfg_lvl():
        print(f"[{_ts()}] [{level.upper()}]", *parts)


# ---------- helpers ----------
SCRIPT_DIR = Path(__file__).resolve().parent


def resolve_base_dir() -> Path:
    env_dir = os.environ.get("VSCODE_EXT_BASE_DIR", "")
    if env_dir:
        p = Path(env_dir).resolve()
        if p.exists():
            return p
    # Try to locate repo root by walking up from the current working directory
    try:
        cur = Path.cwd().resolve()
    except Exception:
        cur = SCRIPT_DIR
    for ancestor in [cur, *cur.parents]:
        flake = ancestor / "flake.nix"
        pkgs_dir = ancestor / "pkgs" / "vscode-extensions"
        if flake.exists() and pkgs_dir.exists():
            return pkgs_dir
    # Fallback to script directory (works when running directly from repo)
    return SCRIPT_DIR


BASE_DIR = resolve_base_dir()

DRY_RUN = os.environ.get("DRY_RUN", "0") == "1"
ALLOW_INSIDERS = os.environ.get("ALLOW_INSIDERS", "0") == "1"
ALLOW_PRERELEASE = os.environ.get("ALLOW_PRERELEASE", "0") == "1"
TARGET_VSCODE_VERSION = os.environ.get("TARGET_VSCODE_VERSION", "")
VSCODE_NIXPKGS_INPUT = os.environ.get(
    "VSCODE_NIXPKGS_INPUT", ""
)  # e.g. "nixpkgs-unstable"
SELECTION_SOURCE = os.environ.get(
    "VSCODE_EXT_SOURCE", "marketplace"
).lower()  # marketplace|github
GITHUB_REPO = os.environ.get(
    "VSCODE_EXT_GITHUB_REPO", ""
)  # e.g. "microsoft/vscode-copilot-chat"
FORCED_VERSION = os.environ.get("VSCODE_EXT_VERSION", "")


class CmdError(Exception):
    pass


def run(cmd: list[str], capture: bool = True, check: bool = True) -> str:
    try:
        res = subprocess.run(
            cmd,
            check=check,
            capture_output=capture,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        raise CmdError(
            f"Command failed: {' '.join(cmd)}\n{e.stderr or e.stdout}"
        ) from e
    return res.stdout if capture else ""


def nix_eval_raw(expr: str) -> str:
    try:
        # Use --impure so getFlake on local path works reliably
        return run(["nix", "eval", "--impure", "--raw", "--expr", expr]).strip()
    except CmdError:
        return ""


def current_system() -> str:
    # builtins.currentSystem requires impure evaluation
    try:
        out = run(
            ["nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem"]
        ).strip()
    except CmdError:
        out = ""
    return out or ""


def get_vscode_version() -> Optional[str]:
    """Resolve target VS Code version from nixpkgs inputs.

    Strategy:
    - Respect TARGET_VSCODE_VERSION if provided.
    - Determine current system via impure nix eval.
    - Import the chosen nixpkgs input with allowUnfree=true and probe attributes
      in order: vscode, code, vscodium. Return the first version found.
    - Try inputs in order: VSCODE_NIXPKGS_INPUT override, then nixpkgs-unstable,
      nixpkgsUnstable, nixpkgs.
    """
    if TARGET_VSCODE_VERSION:
        return TARGET_VSCODE_VERSION

    sysname = current_system()
    if not sysname:
        log("warn", "could not determine current system; defaulting to allow insiders")
        return None

    candidates = []
    if VSCODE_NIXPKGS_INPUT:
        candidates = [VSCODE_NIXPKGS_INPUT]
    else:
        candidates = ["nixpkgs-unstable", "nixpkgsUnstable", "nixpkgs"]

    # Build a nix expression that imports nixpkgs input with allowUnfree=true
    # and then checks attr versions in order.
    def mk_expr(inp: str) -> str:
        return (
            "let flake = builtins.getFlake (toString ./.); "
            f'pkgs = import flake.inputs.{inp} {{ system = "{sysname}"; config = {{ allowUnfree = true; }}; }}; in '
            "(if pkgs ? vscode then pkgs.vscode.version "
            "else if pkgs ? code then pkgs.code.version "
            'else if pkgs ? vscodium then pkgs.vscodium.version else "")'
        )

    for inp in candidates:
        try:
            v = nix_eval_raw(mk_expr(inp))
        except Exception as e:
            log("debug", f"Version probe failed for input '{inp}': {e}")
            v = ""
        if v:
            log("debug", f"Resolved VS Code version {v} from flake input '{inp}'")
            return v

    log(
        "warn",
        "could not evaluate nixpkgs vscode version; defaulting to allow insiders",
    )
    return None


# ---------- VS Marketplace ----------
VSCODE_GALLERY_URL = (
    "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery"
)


def marketplace_query(publisher: str, name: str) -> Dict[str, Any]:
    body = {
        "filters": [
            {
                "criteria": [{"filterType": 7, "value": f"{publisher}.{name}"}],
                "pageNumber": 1,
                "pageSize": 1,
                "sortBy": 0,
                "sortOrder": 0,
            }
        ],
        "assetTypes": [
            "Microsoft.VisualStudio.Services.VSIXPackage",
            "Microsoft.VisualStudio.Code.Manifest",
        ],
        "flags": 914,
    }
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        VSCODE_GALLERY_URL,
        data=data,
        headers={
            "Accept": "application/json; api-version=3.0-preview.1",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _iter_versions(data: Dict[str, Any]):
    try:
        ext = data["results"][0]["extensions"][0]
        for v in ext.get("versions", []):
            ver = v.get("version", "")
            # detect pre-release via properties
            pre = False
            for prop in v.get("properties", []) or []:
                if (
                    str(prop.get("key")) == "Microsoft.VisualStudio.Code.PreRelease"
                    and str(prop.get("value")).lower() == "true"
                ):
                    pre = True
                    break
            yield (ver, pre, v)
    except Exception:
        return


def list_versions(data: Dict[str, Any]) -> list[str]:
    return [ver for (ver, _pre, _vobj) in _iter_versions(data)]


def find_file_url(data: Dict[str, Any], version: str, suffix: str) -> str:
    try:
        ext = data["results"][0]["extensions"][0]
        for v in ext.get("versions", []):
            if v.get("version") != version:
                continue
            for f in v.get("files", []):
                if str(f.get("assetType", "")).endswith(suffix):
                    return f.get("source", "")
    except Exception:
        pass
    return ""


def get_manifest_range(data: Dict[str, Any], version: str) -> str:
    url = find_file_url(data, version, "Code.Manifest")
    if not url:
        return ""
    try:
        with urllib.request.urlopen(url, timeout=15) as resp:
            manifest = json.loads(resp.read().decode("utf-8"))
            return str(manifest.get("engines", {}).get("vscode", ""))
    except Exception:
        return ""


# ---------- compatibility ----------
_semver_pat = re.compile(r"^\d+(?:\.\d+){0,2}$")


def parse_ver(v: str) -> Tuple[int, int, int]:
    if not v:
        return (0, 0, 0)
    parts = v.split(".")[:3]
    while len(parts) < 3:
        parts.append("0")
    try:
        return tuple(int(p) for p in parts)  # type: ignore[return-value]
    except Exception:
        return (0, 0, 0)


def ver_gte(a: str, b: str) -> bool:
    return parse_ver(a) >= parse_ver(b)


_caret = re.compile(r"^\^([0-9]+\.[0-9]+\.[0-9]+)")
_ge = re.compile(r">=([0-9]+\.[0-9]+\.[0-9]+)")
_lt = re.compile(r"<([0-9]+\.[0-9]+\.[0-9]+)")


def engines_compatible(rng: str, target: str) -> bool:
    if not rng or rng == "*":
        return True
    m = _caret.match(rng)
    if m and not ver_gte(target, m.group(1)):
        return False
    m = _ge.search(rng)
    if m and not ver_gte(target, m.group(1)):
        return False
    m = _lt.search(rng)
    if m and not (parse_ver(target) < parse_ver(m.group(1))):
        return False
    return True


def pick_latest_version(
    data: Dict[str, Any], target_vscode: Optional[str]
) -> Tuple[Optional[str], str]:
    # Filter versions by semver shape and prerelease status
    versions = []
    for ver, pre, _vobj in _iter_versions(data):
        if not _semver_pat.match(ver):
            continue
        if pre and not ALLOW_PRERELEASE:
            log("debug", f"Skipping prerelease {ver} (ALLOW_PRERELEASE=0)")
            continue
        versions.append(ver)
    if not versions:
        return None, ""
    if ALLOW_INSIDERS or not target_vscode:
        # absolute latest
        return max(versions, key=parse_ver), ""
    best: Optional[str] = None
    best_rng = ""
    for v in versions:
        rng = get_manifest_range(data, v)
        if engines_compatible(rng, target_vscode):
            if best is None or parse_ver(v) > parse_ver(best):
                best = v
                best_rng = rng
    return best, best_rng


# ---------- GitHub releases ----------
def github_latest_release(repo: str, allow_prerelease: bool = False) -> Optional[str]:
    """Return the latest release tag for the repo.

    If allow_prerelease=False, prefers the stable latest (/releases/latest). If that fails
    or allow_prerelease=True, falls back to /releases and picks the first matching.
    """
    token = os.environ.get("GITHUB_TOKEN", "")
    headers = {"Accept": "application/vnd.github+json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    base = f"https://api.github.com/repos/{repo}"
    # Try stable latest first if not allowing prerelease
    if not allow_prerelease:
        req = urllib.request.Request(f"{base}/releases/latest", headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                j = json.loads(resp.read().decode("utf-8"))
            tag = str(j.get("tag_name", ""))
            if tag:
                return tag
        except Exception as e:
            log("debug", f"GitHub /releases/latest failed: {e}")
    # Fallback: list releases and pick first that matches prerelease policy
    req = urllib.request.Request(f"{base}/releases", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            arr = json.loads(resp.read().decode("utf-8"))
        for rel in arr:
            if rel.get("draft"):
                continue
            if (rel.get("prerelease") or False) and not allow_prerelease:
                continue
            tag = str(rel.get("tag_name", ""))
            if tag:
                return tag
    except Exception as e:
        log("error", f"Failed to query GitHub releases for {repo}: {e}")
    return None


# ---------- nix hash ----------


def prefetch_sri(url: str) -> str:
    try:
        out = run(["nix", "store", "prefetch-file", "--json", url])
        j = json.loads(out)
        return j.get("hash", "")
    except Exception as e:
        log("error", f"prefetch failed: {e}")
        return ""


# ---------- file parsing & update ----------
_mktplc_block_re = re.compile(r"mktplcRef\s*=\s*\{(.*?)\}\s*;", re.S)
_kv_re = re.compile(r"(publisher|name|version)\s*=\s*\"([^\"]+)\"\s*;")


def parse_mktplc_ref(path: Path) -> Tuple[str, str, str]:
    text = path.read_text(encoding="utf-8")
    m = _mktplc_block_re.search(text)
    pub = name = ver = ""
    if m:
        block = m.group(1)
        for k, v in _kv_re.findall(block):
            if k == "publisher":
                pub = v
            elif k == "name":
                name = v
            elif k == "version":
                ver = v
    # fallbacks (best-effort)
    if not pub:
        m2 = re.search(r"publisher\s*=\s*\"([^\"]+)\"\s*;", text)
        if m2:
            pub = m2.group(1)
    if not name:
        # try name within block first
        if m:
            m3 = re.search(r"name\s*=\s*\"([^\"]+)\"\s*;", m.group(1))
            if m3:
                name = m3.group(1)
        if not name:
            m3b = re.search(r"name\s*=\s*\"([^\"]+)\"\s*;", text)
            if m3b:
                name = m3b.group(1)
    return pub, name, ver


def update_file(path: Path, old_version: str, new_version: str, sri: str) -> None:
    text = path.read_text(encoding="utf-8")
    m = _mktplc_block_re.search(text)
    if not m:
        # fallback: global replace (first occurrences)
        text = re.sub(
            rf'version\s*=\s*"{re.escape(old_version)}"\s*;',
            f'version = "{new_version}";',
            text,
            count=1,
        )
        text = re.sub(r'hash\s*=\s*"[^"]+"\s*;', f'hash = "{sri}";', text, count=1)
        path.write_text(text, encoding="utf-8")
        return
    start, end = m.span(1)
    block = text[start:end]
    block = re.sub(
        rf'version\s*=\s*"{re.escape(old_version)}"\s*;',
        f'version = "{new_version}";',
        block,
        count=1,
    )
    block = re.sub(r'hash\s*=\s*"[^"]+"\s*;', f'hash = "{sri}";', block, count=1)
    new_text = text[:start] + block + text[end:]
    path.write_text(new_text, encoding="utf-8")


# ---------- main flow ----------


def update_one(def_file: Path, target_vscode: Optional[str]) -> bool:
    pub, name, cur_ver = parse_mktplc_ref(def_file)
    if not pub or not name or not cur_ver:
        log("warn", f"Skipping {def_file} (could not parse publisher/name/version)")
        return False
    log("info", f"Checking {pub}.{name}")
    log("debug", f"Current in-repo version: {cur_ver}")
    if target_vscode:
        log("debug", f"Target VS Code version: {target_vscode}")
    else:
        log(
            "debug",
            f"Target VS Code version: <unknown> (insiders allowed: {ALLOW_INSIDERS})",
        )

    # Determine desired latest version based on selected source
    try:
        data = marketplace_query(pub, name)
    except Exception as e:
        log("error", f"Failed to query marketplace for {pub}.{name}: {e}")
        return False

    latest = None
    rng = ""
    if SELECTION_SOURCE == "marketplace":
        latest, rng = pick_latest_version(data, target_vscode)
    elif SELECTION_SOURCE == "github":
        # Example: microsoft/vscode-copilot-chat
        repo = GITHUB_REPO or f"{pub}/{name}"
        tag = github_latest_release(repo, allow_prerelease=ALLOW_PRERELEASE)
        if not tag:
            log("error", f"Could not resolve latest GitHub release for {repo}")
            return False
        # Normalize tag like v0.31.2 -> 0.31.2
        latest = tag.lstrip("v")
        # If enforcing compatibility, check manifest of this particular version
        if target_vscode:
            rng = get_manifest_range(data, latest)
            if rng and not engines_compatible(rng, target_vscode):
                log(
                    "error",
                    f"GitHub latest {latest} requires engines.vscode: {rng}, incompatible with {target_vscode}",
                )
                return False
    elif FORCED_VERSION:
        latest = FORCED_VERSION
        if target_vscode:
            rng = get_manifest_range(data, latest)
            if rng and not engines_compatible(rng, target_vscode):
                log(
                    "error",
                    f"Requested version {latest} requires engines.vscode: {rng}, incompatible with {target_vscode}",
                )
                return False
    if not latest:
        # Provide helpful diagnostics
        all_versions = [v for v in list_versions(data) if _semver_pat.match(v)]
        if not all_versions:
            log("error", f"No versions found on Marketplace for {pub}.{name}")
            return False
        if target_vscode:
            top = sorted(all_versions, key=parse_ver, reverse=True)[:3]
            for v in top:
                vrng = get_manifest_range(data, v)
                log(
                    "info",
                    f"Candidate {v} requires engines.vscode: {vrng or '<unspecified>'}",
                )
            log(
                "error",
                f"No marketplace version of {pub}.{name} is compatible with VS Code {target_vscode}.",
            )
            log(
                "info",
                "Hint: try --vscode-input nixpkgs-unstable (newer VS Code) or --allow-insiders to ignore compatibility.",
            )
        else:
            log("error", f"Could not resolve latest version for {pub}.{name}")
        return False
    if rng:
        log("info", f"Latest compatible online: {latest} (engines.vscode: {rng})")
    else:
        log("info", f"Latest online: {latest}")

    if latest == cur_ver:
        log("info", f"Up-to-date ({cur_ver})")
        return False

    if DRY_RUN:
        # In dry-run mode, avoid network prefetch and file edits; just report.
        if rng:
            log(
                "info",
                f"[DRY-RUN] Would update {pub}.{name} from {cur_ver} -> {latest} (engines.vscode: {rng})",
            )
        else:
            log(
                "info",
                f"[DRY-RUN] Would update {pub}.{name} from {cur_ver} -> {latest}",
            )
        return False

    vsix_url = find_file_url(data, latest, "VSIXPackage")
    if not vsix_url:
        vsix_url = f"https://marketplace.visualstudio.com/_apis/public/gallery/publishers/{pub}/vsextensions/{name}/{latest}/vspackage"
    log("debug", f"Prefetching VSIX: {vsix_url}")
    sri = prefetch_sri(vsix_url)
    if not sri:
        log("error", f"Failed to prefetch VSIX for {pub}.{name}")
        return False
    log("debug", f"New SRI: {sri}")

    update_file(def_file, cur_ver, latest, sri)
    log("info", f"Updated {def_file} -> {latest}")
    return True


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(
        description="Update VS Code Marketplace extensions in this repo"
    )
    ap.add_argument(
        "--only",
        nargs=2,
        metavar=("PUBLISHER", "NAME"),
        help="Update only the specified publisher/name",
    )
    ap.add_argument(
        "--allow-insiders",
        action="store_true",
        help="Allow insiders (ignore VS Code compatibility)",
    )
    ap.add_argument(
        "--allow-prerelease",
        action="store_true",
        help="Allow prerelease Marketplace versions",
    )
    ap.add_argument(
        "--target-vscode", help="Explicit VS Code version for compatibility"
    )
    ap.add_argument(
        "--vscode-input",
        help="Flake input name to resolve VS Code from (default: tries nixpkgs-unstable, nixpkgsUnstable, then nixpkgs)",
    )
    ap.add_argument(
        "--source",
        choices=["marketplace", "github"],
        help="Version source to use (default: marketplace)",
    )
    ap.add_argument(
        "--github-repo",
        help="GitHub repo 'owner/name' for release lookup (default: <publisher>/<name>)",
    )
    ap.add_argument(
        "--version", dest="forced_version", help="Force a specific extension version"
    )
    args = ap.parse_args(argv)
    # Preflight: mitigate git fsmonitor issues that can break builtins.getFlake
    try:
        repo_git = Path.cwd() / ".git"
        ipc = repo_git / "fsmonitor--daemon.ipc"
        if ipc.exists():
            try:
                ipc.unlink()
                log("debug", "Removed .git/fsmonitor--daemon.ipc to appease nix eval")
            except Exception as e:
                log("debug", f"Could not remove fsmonitor ipc: {e}")
        # Optionally unset core.fsmonitor if set
        try:
            _ = run(
                ["git", "config", "--local", "--get", "core.fsmonitor"],
                capture=True,
                check=False,
            )
            run(
                ["git", "config", "--local", "--unset", "core.fsmonitor"],
                capture=True,
                check=False,
            )
        except Exception:
            pass
    except Exception:
        pass

    if args.allow_insiders:
        global ALLOW_INSIDERS
        ALLOW_INSIDERS = True
    if args.allow_prerelease:
        global ALLOW_PRERELEASE
        ALLOW_PRERELEASE = True
    if args.target_vscode:
        global TARGET_VSCODE_VERSION
        TARGET_VSCODE_VERSION = args.target_vscode
    if args.vscode_input:
        global VSCODE_NIXPKGS_INPUT
        VSCODE_NIXPKGS_INPUT = args.vscode_input
    if args.source:
        global SELECTION_SOURCE
        SELECTION_SOURCE = args.source
    if args.github_repo:
        global GITHUB_REPO
        GITHUB_REPO = args.github_repo
    if args.forced_version:
        global FORCED_VERSION
        FORCED_VERSION = args.forced_version

    updated_any = False
    matched_any = False

    if ALLOW_INSIDERS:
        log("info", "ALLOW_INSIDERS=1 — ignoring VS Code compatibility")
        target_vscode = None
    else:
        tv = get_vscode_version()
        if tv:
            log("info", f"Target VS Code: {tv}")
            target_vscode = tv
        else:
            log("info", "Target VS Code: <unknown> (falling back to allow insiders)")
            target_vscode = None

    if ALLOW_PRERELEASE:
        log("info", "ALLOW_PRERELEASE=1 — prerelease Marketplace versions permitted")

    for def_file in sorted(BASE_DIR.glob("*/default.nix")):
        if def_file == BASE_DIR / "default.nix":
            continue
        log("debug", f"Found definition: {def_file}")
        pub, name, _ = parse_mktplc_ref(def_file)
        log("debug", f"Parsed publisher={pub} name={name}")
        if args.only and (pub != args.only[0] or name != args.only[1]):
            log(
                "debug",
                f"Skipping due to --only mismatch (wanted {args.only[0]}.{args.only[1]})",
            )
            continue
        matched_any = True
        if update_one(def_file, target_vscode):
            updated_any = True

    if not updated_any:
        if args.only and not matched_any:
            log("info", f"No packages matched --only {args.only[0]}.{args.only[1]}")
        else:
            log("info", "No updates performed.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
