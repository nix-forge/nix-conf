#!/usr/bin/env bash
set -euo pipefail

# Update all VS Code Marketplace extensions under pkgs/vscode-extensions/*/default.nix
# Pattern based on other update scripts in this repo (arkenfox-user-js, ttf-ms-win11-auto).
#
# Requirements (provided via writeShellApplication runtimeInputs):
# - curl, jq, sed (GNU), coreutils, nix, python3
#
# Behavior:
# - For each extension definition, query the Marketplace API for the latest version
# - Resolve the VSIX download URL from the response (fallback to canonical vspackage URL)
# - Prefetch to compute SRI hash
# - Patch version and hash in the default.nix if an update is available
#
# Notes:
# - Respects DRY_RUN=1 to show changes without modifying files

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BASE_DIR="$REPO_ROOT/pkgs/vscode-extensions"

if [[ ! -d $BASE_DIR ]]; then
  echo "vscode-extensions directory not found: $BASE_DIR" >&2
  exit 1
fi

DRY_RUN="${DRY_RUN:-0}"
ONLY_PUBLISHER=""
ONLY_NAME=""

if [[ ${1:-} == "--only" ]]; then
  if [[ $# -lt 3 ]]; then
    echo "Usage: $0 [--only <publisher> <name>]" >&2
    exit 2
  fi
  ONLY_PUBLISHER="$2"
  ONLY_NAME="$3"
  shift 3
fi

marketplace_query() {
  local publisher="$1" name="$2" out_json="$3"
  local query_body
  query_body=$(
    PUBLISHER="$publisher" EXTNAME="$name" python3 - <<'PY'
import json, os, sys
publisher = os.environ['PUBLISHER']
name = os.environ['EXTNAME']
data = {
  "filters": [
    {
      "criteria": [
        {"filterType": 7, "value": f"{publisher}.{name}"}
      ],
      "pageNumber": 1,
      "pageSize": 1,
      "sortBy": 0,
      "sortOrder": 0
    }
  ],
  "assetTypes": [
    "Microsoft.VisualStudio.Services.VSIXPackage"
  ],
  "flags": 914
}
print(json.dumps(data))
PY
  )
  curl -fsSL \
    -H 'Accept: application/json; api-version=3.0-preview.1' \
    -H 'Content-Type: application/json' \
    --data "$query_body" \
    'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery' \
    -o "$out_json"
}

extract_latest_version() {
  local json_file="$1"
  # Get the maximum semver-like version from the response
  jq -r '[.results[0].extensions[0].versions[].version
          | select(test("^\\d+(\\.\\d+)*$"))
          | split(".") | map(tonumber)]
        | max // empty
        | map(tostring) | join(".")' "$json_file"
}

extract_vsix_url() {
  local json_file="$1" version="$2"
  jq -r --arg ver "$version" \
    '.results[0].extensions[0].versions[]
      | select(.version == $ver)
      | .files[]
      | select(.assetType | endswith("VSIXPackage"))
      | .source // empty' "$json_file"
}

prefetch_sri() {
  local url="$1"
  nix store prefetch-file --json "$url" | jq -r '.hash'
}

update_one() {
  local def_file="$1"

  local publisher name current_version
  publisher=$(awk -F'"' '/publisher *=/ {print $2; exit}' "$def_file" || true)
  name=$(awk -F'"' '/name *=/ {print $2; exit}' "$def_file" || true)
  current_version=$(awk -F'"' '/version *=/ {print $2; exit}' "$def_file" || true)

  if [[ -z $publisher || -z $name || -z $current_version ]]; then
    echo "Skipping $def_file (could not parse publisher/name/version)" >&2
    return 0
  fi

  echo "Checking ${publisher}.${name} (current $current_version)"

  local tmp_json
  tmp_json="$(mktemp)"

  if ! marketplace_query "$publisher" "$name" "$tmp_json"; then
    echo "Failed to query marketplace for ${publisher}.${name}" >&2
    rm -f "$tmp_json"
    return 1
  fi

  local latest_version
  latest_version=$(extract_latest_version "$tmp_json")
  if [[ -z $latest_version ]]; then
    echo "Could not resolve latest version for ${publisher}.${name}" >&2
    rm -f "$tmp_json"
    return 1
  fi

  if [[ $latest_version == "$current_version" ]]; then
    echo "  Up-to-date ($current_version)"
    rm -f "$tmp_json"
    return 0
  fi

  local vsix_url
  vsix_url=$(extract_vsix_url "$tmp_json" "$latest_version")
  if [[ -z $vsix_url ]]; then
    # Fallback canonical URL pattern
    vsix_url="https://marketplace.visualstudio.com/_apis/public/gallery/publishers/${publisher}/vsextensions/${name}/${latest_version}/vspackage"
  fi

  echo "  Latest: $latest_version"
  echo "  Prefetching: $vsix_url"
  local sri
  sri=$(prefetch_sri "$vsix_url")
  if [[ -z $sri || $sri == "null" ]]; then
    echo "  Failed to prefetch VSIX for ${publisher}.${name}" >&2
    rm -f "$tmp_json"
    return 1
  fi

  echo "  New hash: $sri"

  if [[ $DRY_RUN == "1" ]]; then
    echo "  [DRY-RUN] Would update $def_file"
    rm -f "$tmp_json"
    return 0
  fi

  local tmp_file
  tmp_file="$(mktemp)"

  cp "$def_file" "$tmp_file"
  sed -i \
    -e "s/version = \"${current_version}\";/version = \"${latest_version}\";/" \
    -e "s|hash = \".*\";|hash = \"${sri}\";|" \
    "$tmp_file"

  mv "$tmp_file" "$def_file"
  echo "  Updated $def_file -> ${latest_version}"
  rm -f "$tmp_json"
}

shopt -s nullglob
updated_any=0
for def in "$BASE_DIR"/*/default.nix; do
  # Skip the root default
  if [[ $def == "$BASE_DIR/default.nix" ]]; then
    continue
  fi
  if [[ -n $ONLY_PUBLISHER || -n $ONLY_NAME ]]; then
    # Parse file publisher/name to decide whether to run
    file_pub=$(awk -F'"' '/publisher *=/ {print $2; exit}' "$def" || true)
    file_name=$(awk -F'"' '/name *=/ {print $2; exit}' "$def" || true)
    if [[ $file_pub != "$ONLY_PUBLISHER" || $file_name != "$ONLY_NAME" ]]; then
      continue
    fi
  fi
  if update_one "$def"; then
    updated_any=1
  fi
done

if [[ $updated_any == "0" ]]; then
  echo "No updates performed."
fi
