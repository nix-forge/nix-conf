#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
pkg_file="$repo_root/pkgs/arkenfox-user-js/default.nix"

if [[ ! -f $pkg_file ]]; then
	echo "Package definition not found: $pkg_file" >&2
	exit 1
fi

current_version=$(awk -F'"' '/version =/ { print $2; exit }' "$pkg_file")

latest_version=$(
	python3 - <<'PY'
import re
import subprocess
import sys

cmd = [
    "git",
    "ls-remote",
    "--tags",
    "--refs",
    "https://github.com/arkenfox/user.js",
]

try:
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
except subprocess.CalledProcessError as exc:
    if exc.stderr:
        print(exc.stderr, file=sys.stderr)
    sys.exit("Failed to list tags from arkenfox/user.js")

best_tuple = None
best_version = None

for line in result.stdout.splitlines():
    parts = line.strip().split("\t", 1)
    if len(parts) != 2:
        continue
    ref = parts[1]
    tag = ref.removeprefix("refs/tags/").removesuffix("^{}")
    if not re.fullmatch(r"v?\d+(\.\d+)*", tag):
        continue
    normalized = tag[1:] if tag.startswith("v") else tag
    try:
        version_tuple = tuple(int(p) for p in normalized.split("."))
    except ValueError:
        continue
    if best_tuple is None or version_tuple > best_tuple:
        best_tuple = version_tuple
        best_version = normalized

if best_version is None:
    sys.exit("Could not determine latest arkenfox release tag")

print(best_version)
PY
)

if [[ -z $latest_version || $latest_version == "null" ]]; then
	echo "Unable to determine latest version." >&2
	exit 1
fi

if [[ $current_version == "$latest_version" ]]; then
	echo "arkenfox-user-js is already at version $latest_version"
	exit 0
fi

url="https://raw.githubusercontent.com/arkenfox/user.js/${latest_version}/user.js"
echo "Prefetching $url"
hash=$(nix store prefetch-file --json "$url" | jq -r '.hash')

tmp_file=$(mktemp)
trap 'rm -f "$tmp_file" "$tmp_file".bak' EXIT

cp "$pkg_file" "$tmp_file"
sed -i \
	-e "s/version = \"${current_version}\";/version = \"${latest_version}\";/" \
	-e "s|sha256 = \".*\";|sha256 = \"${hash}\";|" \
	"$tmp_file"

mv "$tmp_file" "$pkg_file"

echo "Updated arkenfox-user-js to $latest_version"
