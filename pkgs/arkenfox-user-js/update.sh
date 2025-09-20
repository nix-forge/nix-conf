#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
pkg_file="$repo_root/pkgs/arkenfox-user-js/default.nix"

if [[ ! -f $pkg_file ]]; then
  echo "Package definition not found: $pkg_file" >&2
  exit 1
fi

current_version=$(awk -F'"' '/version =/ { print $2; exit }' "$pkg_file")
latest_tag=$(git ls-remote --tags --refs https://github.com/arkenfox/user.js 'v*' |
  awk '{print $2}' |
  sed 's#refs/tags/##' |
  sed 's/\^{}$//' |
  sort -V |
  tail -n1)
latest_version="${latest_tag#v}"

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
