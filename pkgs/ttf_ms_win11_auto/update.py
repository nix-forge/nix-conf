#!/usr/bin/env python3
"""
Update the `ttf-ms-win11-auto` package metadata to the latest Windows 11 ISO.

Usage
-----
    python update.py \
      --package-file pkgs/ttf-ms-win11-auto/default.nix \
      --page-url https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise \
      --locale en-US

If `--package-file` is omitted, the script assumes it lives next to this file
(`./default.nix`).

Environment overrides
---------------------
- EVALCENTER_URL, LOCALE, PACKAGE_FILE, NIX_BIN

Exit codes
----------
- 0: success (updated or already up-to-date)
- 1: fatal error
- 130: interrupted

Notes
-----
- This script **does not** commit to git. Your outer automation can do that.
- It updates only obvious attributes. If your `default.nix` uses custom names,
  pass `--attr-version`, `--attr-url`, `--attr-hash`, or `--attr-sha256`.
"""

from __future__ import annotations

import argparse
import dataclasses as dc
import difflib
import json
import logging
import os
import re
import shlex
import subprocess
from html import unescape
from html.parser import HTMLParser
from pathlib import Path
import sys
from typing import Any, Final, Optional, Sequence
from urllib.parse import urlparse, urlunparse

import requests
from requests.adapters import HTTPAdapter
from urllib3.util import Retry


# -----------------------------
# Defaults (overridable via CLI/ENV)
# -----------------------------
DEFAULT_PAGE_URL: Final[str] = (
    "https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise"
)
DEFAULT_LOCALE: Final[str] = "en-US"
DEFAULT_USER_AGENT: Final[str] = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/127 Safari/537.36"
)
DEFAULT_TIMEOUT: Final[float] = 25.0

# Attribute names inside default.nix. Can be overridden via CLI.
ATTR_VERSION: Final[str] = "version"
ATTR_URL: Final[str] = "url"
ATTR_HASH_SRI: Final[str] = "hash"  # modern style: hash = "sha256-...";
ATTR_HASH_B32: Final[str] = "sha256"  # legacy style: sha256 = "...";

# nix invocations
NIX_BIN: Final[str] = os.environ.get("NIX_BIN", "nix")
PREFETCH_CMD: Final[tuple[str, ...]] = (NIX_BIN, "store", "prefetch-file", "--json")
HASH_CONVERT_CMD: Final[tuple[str, ...]] = (
    NIX_BIN,
    "hash",
    "convert",
    "--from",
    "sri",
    "--to",
    "nix32",
)

LOG = logging.getLogger("ttf-ms-win11-auto.update")


# -----------------------------
# Data models
# -----------------------------
@dc.dataclass
class ISOInfo:
    url: str
    filename: str
    version: str  # best-effort version string (e.g. "10.0.26100.2134" or "24H2")


@dc.dataclass
class NixHashes:
    sri: str  # e.g. "sha256-…"
    nix32: str  # base32 for legacy sha256 attr


# -----------------------------
# HTTP session with retries
# -----------------------------
def build_http_session(
    user_agent: str = DEFAULT_USER_AGENT,
    total_retries: int = 5,
    backoff_factor: float = 0.3,
) -> requests.Session:
    s = requests.Session()
    s.headers.update({"User-Agent": user_agent, "Accept-Language": "*"})
    retry: Any = Retry(
        total=total_retries,
        read=total_retries,
        connect=total_retries,
        status=total_retries,
        backoff_factor=backoff_factor,
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=("GET", "HEAD"),
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retry)
    s.mount("http://", adapter)
    s.mount("https://", adapter)
    return s


# -----------------------------
# Discovery of the latest ISO URL
# -----------------------------
ISO_URL_RX = re.compile(r"https?://[^\s'\"]+\.iso(?:\?[^'\"\s<>]+)?", re.I)
FWLINK_RX = re.compile(r"https?://go\.microsoft\.com/fwlink/[^'\"\s<>]+", re.I)
FWLINK_ALT_RX = re.compile(r"https?://go\.microsoft\.com/fwlink/p/?[^'\"\s<>]*", re.I)
BUILD_RX = re.compile(r"(?:(?:10\.0\.)?(?P<build>\d{5})(?:\.(?P<rev>\d+))?)")
H2_RX = re.compile(r"(?P<h2>\d{2}H[12])", re.I)


def fetch_text(session: requests.Session, url: str) -> str:
    LOG.debug("GET %s", url)
    r = session.get(url, timeout=DEFAULT_TIMEOUT)
    r.raise_for_status()
    return r.text


def resolve_redirect(session: requests.Session, url: str) -> str:
    """Follow redirects (fwlink or similar) and return the final URL."""
    LOG.debug("HEAD %s (resolve)", url)
    # Some endpoints don't like HEAD; fall back to GET with stream=False
    try:
        resp = session.head(url, allow_redirects=True, timeout=DEFAULT_TIMEOUT)
        if resp.is_redirect or resp.is_permanent_redirect:
            # requests already followed; fallthrough
            pass
        if resp.url and resp.url != url:
            return resp.url
    except Exception:  # servers sometimes block HEAD
        resp = session.get(url, allow_redirects=True, timeout=DEFAULT_TIMEOUT)
    final = resp.url or url
    LOG.debug("Resolved %s -> %s", url, final)
    return final


def choose_best_iso(
    resolved_candidates: Sequence[tuple[str, str]], locale: str
) -> tuple[str, str]:
    """Pick the most plausible candidate ISO URL.

    ``resolved_candidates`` should contain ``(final_url, filename)`` pairs where
    ``filename`` already reflects the resolved download URL.
    """
    if not resolved_candidates:
        raise RuntimeError("No ISO links found on the page")

    # Language hint heuristics
    lang_hints = {
        "en-US": ("English", "en-us", "enu", "english"),
        "en-GB": ("English", "en-gb", "eng", "english"),
    }
    hints = lang_hints.get(locale.upper(), ())

    def score(item: tuple[str, str]) -> int:
        url, name = item
        s = 0
        if any(h in name for h in hints):
            s += 10
        if name.lower().endswith(".iso"):
            s += 2
        if "x64" in name.lower():
            s += 1
        return s

    ranked = sorted(resolved_candidates, key=score, reverse=True)
    return ranked[0]


def candidate_page_urls(page_url: str) -> list[str]:
    """Return the primary page and best-effort fallback URLs to inspect."""

    def norm(u: str) -> str:
        return u.rstrip("/") or u

    urls: list[str] = []
    seen: set[str] = set()

    def add(u: str) -> None:
        key = norm(u)
        if key not in seen:
            seen.add(key)
            urls.append(u)

    parsed = urlparse(page_url)
    if parsed.scheme and parsed.netloc and "evaluate-" in parsed.path:
        alt_path = parsed.path.replace("/evaluate-", "/download-", 1)
        alt_url = urlunparse(parsed._replace(path=alt_path))
        add(alt_url)

    add(page_url)

    return urls


class AnchorCollector(HTMLParser):
    """Collect anchor tags with attributes and text for prioritization."""

    def __init__(self) -> None:
        super().__init__()
        self.links: list[tuple[str, dict[str, str], str]] = []
        self._active: Optional[dict[str, Any]] = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, Optional[str]]]) -> None:
        if tag.lower() != "a":
            return
        attr_map = {k.lower(): (v or "") for k, v in attrs}
        href = (
            attr_map.get("href")
            or attr_map.get("data-href")
            or attr_map.get("data-target")
        )
        if not href:
            return
        self._active = {
            "href": unescape(href.strip()),
            "attrs": attr_map,
            "text": [],
        }

    def handle_data(self, data: str) -> None:
        if self._active is not None:
            self._active["text"].append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() != "a" or self._active is None:
            return
        text = unescape("".join(self._active["text"]).strip())
        href = self._active["href"]
        attrs = self._active["attrs"]
        self.links.append((href, attrs, text))
        self._active = None


def prioritized_links(html: str, locale: str) -> list[str]:
    """Extract and rank link candidates likely to point to the ISO."""

    collector = AnchorCollector()
    try:
        collector.feed(html)
    except Exception as exc:  # HTMLParser can raise on malformed markup
        LOG.debug("Anchor parsing failed: %s", exc)
    hints = locale.lower().split("-")
    scored: list[tuple[int, int, str]] = []
    for idx, (href, attrs, text) in enumerate(collector.links):
        url = href.strip()
        if not url.lower().startswith("http"):
            continue
        lowered = url.lower()
        if "go.microsoft.com" not in lowered and not lowered.endswith(".iso"):
            continue

        score = 0
        if lowered.endswith(".iso"):
            score += 200
        if "go.microsoft.com" in lowered:
            score += 20

        label = text.lower()
        if "download" in label and "iso" in label:
            score += 60
        if "enterprise" in label:
            score += 10
        if "ltsc" in label:
            score -= 15
        if any(part in label for part in hints if part):
            score += 5

        data_tags = attrs.get("data-bi-tags", "").lower()
        if "iso" in data_tags:
            score += 70
        if "iso-dl" in data_tags:
            score += 20
        if "win11entisodlintent" in data_tags:
            score += 20
        if "arm64" in data_tags:
            score -= 5
        if "ltsc" in data_tags:
            score -= 35

        score += max(0, 10 - idx)  # preserve early anchors modestly
        if "64" in label or "64" in attrs.get("data-bi-cn", ""):
            score += 5

        linkid_match = re.search(r"linkid=([0-9]+)", lowered)
        if linkid_match:
            try:
                linkid_val = int(linkid_match.group(1))
            except ValueError:
                linkid_val = None
            if linkid_val is not None:
                if linkid_val >= 2280000:
                    score += 25
                elif linkid_val < 2200000:
                    score -= 20

        scored.append((score, idx, url))

    scored.sort(key=lambda tup: (-tup[0], tup[1]))
    ordered_urls = [url for _score, _idx, url in scored]
    return ordered_urls


def discover_latest_iso(
    session: requests.Session, page_url: str, locale: str
) -> ISOInfo:
    pages = candidate_page_urls(page_url)
    last_non_iso: list[str] = []
    locale_lower = locale.lower()
    locale_tokens = {locale_lower}
    if "-" in locale_lower:
        prefix, suffix = locale_lower.split("-", 1)
        locale_tokens.add(prefix)
        locale_tokens.add(locale_lower.replace("-", ""))
        locale_tokens.add(suffix)

    for candidate_page in pages:
        LOG.debug("Scanning page for ISO links: %s", candidate_page)
        try:
            html = fetch_text(session, candidate_page)
        except requests.RequestException as exc:
            LOG.debug("Failed to fetch %s: %s", candidate_page, exc)
            continue
        text = unescape(html)

        priority = prioritized_links(html, locale)
        iso_links = ISO_URL_RX.findall(text)
        fwlinks = [
            *FWLINK_RX.findall(text),
            *FWLINK_ALT_RX.findall(text),
        ]
        combined = [*priority, *iso_links, *fwlinks]
        ordered = list(dict.fromkeys(combined))
        LOG.debug(
            "Evaluating %d candidate links (top 5 shown): %s", len(ordered), ordered[:5]
        )

        if not ordered:
            LOG.debug("No ISO/fwlink candidates found on %s", candidate_page)
            continue

        resolved: list[tuple[str, str]] = []
        max_resolved = 6
        for candidate in ordered:
            final_url = candidate
            if "fwlink" in candidate or not candidate.lower().endswith(".iso"):
                try:
                    final_url = resolve_redirect(session, candidate)
                except Exception as exc:
                    LOG.debug("Failed to resolve %s: %s", candidate, exc)
                    final_url = candidate
            filename = Path(final_url.split("?", 1)[0]).name
            if filename.lower().endswith(".iso"):
                resolved.append((final_url, filename))
                lower_name = filename.lower()
                if any(token and token in lower_name for token in locale_tokens):
                    LOG.debug("Selected locale-matching candidate: %s", filename)
                    break
                if len(resolved) >= max_resolved:
                    LOG.debug(
                        "Reached max resolved candidates (%d); stopping search on this page.",
                        max_resolved,
                    )
                    break
            else:
                last_non_iso.append(final_url)

        if resolved:
            final_url, filename = choose_best_iso(resolved, locale)
            version = infer_version(filename) or infer_version(final_url) or "unknown"
            return ISOInfo(url=final_url, filename=filename, version=version)

    extra = ""
    if last_non_iso:
        extra = f" Last non-ISO candidate: {last_non_iso[-1]}"
    raise RuntimeError(
        "Could not locate a direct ISO download from Microsoft Evaluation Center pages."
        + extra
    )


def infer_version(s: str) -> Optional[str]:
    # Try build like 10.0.26100.2134 or 26100 or 26100.2134
    if m := BUILD_RX.search(s):
        build = m.group("build")
        rev = m.group("rev")
        return f"10.0.{build}.{rev}" if rev else f"10.0.{build}"
    # Try 24H2/23H2 tags
    if m := H2_RX.search(s):
        return m.group("h2").upper()
    return None


# -----------------------------
# Nix hashing helpers
# -----------------------------


def run(cmd: Sequence[str]) -> subprocess.CompletedProcess[str]:
    LOG.debug("+ %s", " ".join(map(shlex.quote, cmd)))
    return subprocess.run(cmd, check=True, text=True, capture_output=True)


def nix_prefetch_sri(url: str) -> str:
    cp = run([*PREFETCH_CMD, url])
    data = json.loads(cp.stdout)
    sri = data.get("hash")
    if not isinstance(sri, str) or not sri.startswith("sha256-"):
        raise RuntimeError("nix prefetch returned unexpected JSON: missing SRI hash")
    return sri


def sri_to_nix32(sri: str) -> str:
    cp = run([*HASH_CONVERT_CMD, sri])
    out = cp.stdout.strip()
    if not out:
        raise RuntimeError("nix hash convert produced empty output")
    return out


# -----------------------------
# Nix file update
# -----------------------------


@dc.dataclass
class UpdatePlan:
    before: str
    after: str
    changed: bool


def update_default_nix(
    content: str,
    *,
    version_attr: str,
    url_attr: str,
    iso_url: str,
    version: str,
    sri_hash: Optional[str],
    nix32_hash: Optional[str],
    prefer_sri_attr: bool = True,
) -> UpdatePlan:
    """Return updated content; update only attrs that exist."""
    before = content

    def repl_attr(txt: str, attr: str, value: str) -> str:
        pattern = rf'({re.escape(attr)}\s*=\s*")([^"]*)("\s*;)'
        rx = re.compile(pattern, re.M)
        if rx.search(txt):
            return rx.sub(lambda m: f"{m.group(1)}{value}{m.group(3)}", txt)
        return txt

    # Update version, url
    content = repl_attr(content, version_attr, version)
    content = repl_attr(content, url_attr, iso_url)

    if prefer_sri_attr:
        sri_updated = False
        if sri_hash is not None:
            new_content = repl_attr(content, ATTR_HASH_SRI, sri_hash)
            sri_updated = new_content != content
            content = new_content
        if nix32_hash is not None and (
            sri_hash is None or not sri_updated or ATTR_HASH_SRI not in before
        ):
            content = repl_attr(content, ATTR_HASH_B32, nix32_hash)
    else:
        if nix32_hash is not None:
            content = repl_attr(content, ATTR_HASH_B32, nix32_hash)
        if sri_hash is not None:
            content = repl_attr(content, ATTR_HASH_SRI, sri_hash)

    changed = content != before
    return UpdatePlan(before=before, after=content, changed=changed)


def find_attr_value(content: str, attr: str) -> Optional[str]:
    pattern = rf"{re.escape(attr)}\s*=\s*\"([^\"]*)\""
    if match := re.search(pattern, content):
        return match.group(1)
    return None


# -----------------------------
# CLI
# -----------------------------


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--page-url", default=os.environ.get("EVALCENTER_URL", DEFAULT_PAGE_URL)
    )
    p.add_argument("--locale", default=os.environ.get("LOCALE", DEFAULT_LOCALE))
    p.add_argument("--package-file", default=os.environ.get("PACKAGE_FILE"))
    p.add_argument("--attr-version", default=ATTR_VERSION)
    p.add_argument("--attr-url", default=ATTR_URL)
    p.add_argument(
        "--prefer-sri",
        action="store_true",
        help="Prefer updating 'hash' (SRI) for modern Nix",
    )
    p.add_argument(
        "--prefetch",
        action="store_true",
        help=(
            "Force a Nix prefetch to recompute hashes even during dry-run or when the version"
            " is unchanged (downloads the ISO)."
        ),
    )
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--verbose", "-v", action="count", default=0)
    return p.parse_args(argv)


def default_package_file(cli_value: Optional[str]) -> Path:
    if cli_value:
        return Path(cli_value)
    # default: sibling default.nix
    here = Path(__file__).resolve()
    return here.with_name("default.nix")


# -----------------------------
# Main
# -----------------------------


def main(argv: Optional[Sequence[str]] = None) -> int:
    ns = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if ns.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )

    pkg_file = default_package_file(ns.package_file)
    if not pkg_file.exists():
        LOG.error("Package file not found: %s", pkg_file)
        return 1

    text = pkg_file.read_text(encoding="utf-8")
    existing_version = find_attr_value(text, ns.attr_version)

    session = build_http_session()
    LOG.info("Discovering latest Windows 11 Enterprise ISO…")
    iso = discover_latest_iso(session, ns.page_url, ns.locale)
    LOG.info("Found: %s (version hint: %s)", iso.filename, iso.version)

    sri: Optional[str] = None
    nix32: Optional[str] = None

    version_changed = existing_version is None or iso.version != existing_version
    prefetch_requested = bool(ns.prefetch)
    should_prefetch = False
    message: Optional[str] = None

    if prefetch_requested:
        should_prefetch = True
        if ns.dry_run:
            message = "Prefetch flag supplied during dry-run; prefetching via Nix to compute hash (this may take a while)…"
        elif not version_changed:
            message = (
                "Prefetch flag supplied; prefetching via Nix to compute hash even though version is unchanged (%s). This may take a while…"
                % (iso.version,)
            )
        else:
            message = "Prefetch flag supplied; prefetching via Nix to compute hash (this may take a while)…"
    else:
        if ns.dry_run:
            message = "Dry-run detected; skipping prefetch (hash unchanged). Pass --prefetch to prefetch during dry-run."
        elif version_changed:
            message = (
                "Version changed from %s to %s; prefetching via Nix to compute hash (default; this may take a while)…"
                % (existing_version or "unknown", iso.version)
            )
            should_prefetch = True
        else:
            message = (
                "Version unchanged (%s); skipping prefetch (hash unchanged). Use --prefetch to force."
                % (iso.version,)
            )

    if message:
        LOG.info(message)

    if should_prefetch:
        sri = nix_prefetch_sri(iso.url)
        try:
            nix32 = sri_to_nix32(sri)
        except Exception as e:
            LOG.warning("Could not convert SRI to nix32: %s", e)
            nix32 = None
        else:
            LOG.info("Converted SRI hash to nix32 format.")

    plan = update_default_nix(
        text,
        version_attr=ns.attr_version,
        url_attr=ns.attr_url,
        iso_url=iso.url,
        version=iso.version,
        sri_hash=sri,
        nix32_hash=nix32,
        prefer_sri_attr=ns.prefer_sri,
    )

    if not plan.changed:
        LOG.info("No changes detected; already up-to-date.")
        return 0

    if ns.dry_run:
        LOG.info("Dry-run: showing diff (no write)")
        for line in difflib.unified_diff(
            plan.before.splitlines(keepends=False),
            plan.after.splitlines(keepends=False),
            fromfile=str(pkg_file),
            tofile=str(pkg_file),
            lineterm="",
        ):
            sys.stdout.write(line + "\n")
        return 0

    pkg_file.write_text(plan.after, encoding="utf-8")
    LOG.info("Updated %s", pkg_file)
    LOG.info("New version: %s", iso.version)
    LOG.info("New URL: %s", iso.url)
    if sri is not None:
        LOG.info("New hash (SRI): %s", sri)
    if nix32 is not None:
        LOG.info("New sha256 (nix32): %s", nix32)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        LOG.error("Aborted by user")
        raise SystemExit(130)
