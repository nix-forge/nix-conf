#!/usr/bin/env bash
set -euo pipefail

PAGE_URL="https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise"
LOCALE="${ISO_LOCALE:-en-US}"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PKG_FILE="$REPO_ROOT/pkgs/ttf-ms-win11-auto/default.nix"

if [[ ! -f $PKG_FILE ]]; then
  echo "Package definition not found: $PKG_FILE" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

page_html="$tmp_dir/page.html"
curl -fsSL --compressed \
  -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36' \
  "$PAGE_URL" -o "$page_html"

readarray -t resolved < <(
  python3 - "$page_html" "$LOCALE" <<'PY'
import html
import re
import sys
import urllib.request

page_path, locale = sys.argv[1:3]
with open(page_path, encoding="utf-8", errors="ignore") as fh:
    text = html.unescape(fh.read())

pattern = re.compile(
    rf'Download\s+Windows\s+11\s+Enterprise\s+ISO\s+64-bit\s+\({re.escape(locale)}\).*?href="(https://go\.microsoft\.com/[^"]+)"',
    re.IGNORECASE | re.DOTALL,
)
match = pattern.search(text)
if not match:
    raise SystemExit("Failed to locate download link in evaluation page")
fwlink = match.group(1)

request = urllib.request.Request(fwlink, method="HEAD")
with urllib.request.urlopen(request) as response:
    iso_url = response.geturl()

build_match = re.search(r"/(\d+)\.(\d+)\.", iso_url)
if not build_match:
    raise SystemExit("Failed to derive build information from ISO URL")
build, patch = build_match.groups()
pkgver = f"10.0.{build}.{patch}"

print(iso_url)
print(pkgver)
PY
)

iso_url="${resolved[0]:-}"
pkgver="${resolved[1]:-}"

if [[ -z $iso_url || -z $pkgver ]]; then
  echo "Unable to resolve ISO URL or version" >&2
  exit 1
fi

echo "Resolved ISO URL: $iso_url"
echo "Resolved version: $pkgver"

echo "Prefetching ISO to obtain hash (may download several GiB)..."
prefetch_json=$(nix store prefetch-file --json "$iso_url" 2>"$tmp_dir/prefetch.log" || {
  cat "$tmp_dir/prefetch.log" >&2
  exit 1
})

sri_hash=$(printf '%s' "$prefetch_json" | jq -r '.hash')
if [[ -z $sri_hash || $sri_hash == "null" ]]; then
  echo "Failed to determine ISO hash" >&2
  exit 1
fi

nix_sha=$(nix hash convert --from sri --to nix32 "$sri_hash")

echo "Computed Nix hash: $nix_sha"

python3 - "$PKG_FILE" "$pkgver" "$iso_url" "$nix_sha" <<'PY'
import re
import sys

path, version, url, sha = sys.argv[1:5]
with open(path, "r", encoding="utf-8") as fh:
    text = fh.read()

patterns = {
    r'version = "[^"]*";': f'version = "{version}";',
    r'url = "[^"]*";': f'url = "{url}";',
    r'sha256 = "[^"]*";': f'sha256 = "{sha}";',
}

for pattern, replacement in patterns.items():
    text, count = re.subn(pattern, replacement, text, count=1)
    if count == 0:
        raise SystemExit(f"Failed to update pattern: {pattern}")

with open(path, "w", encoding="utf-8") as fh:
    fh.write(text)
PY

echo "Updated $PKG_FILE to version $pkgver"
