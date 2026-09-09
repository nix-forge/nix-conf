#!/usr/bin/env bash
set -euo pipefail

# flake.nix uses path:./pkgs. Read the policy from that same checkout so updates
# to the package submodule also update hosted-build eligibility here.
policy=pkgs/.github/ci-policy.json
if ! jq -e '
  type == "object" and all(to_entries[];
    (.key | test("^[a-z0-9][a-z0-9+._-]*$")) and
    (.value | type == "string" and test("\\S")))
' "$policy" >/dev/null; then
  echo '::error::Invalid hosted-build policy in pkgs; expected package names and nonblank reasons.' >&2
  exit 1
fi
while IFS= read -r package; do
  if [[ ! -f "pkgs/pkgs/by-name/${package:0:2}/$package/package.nix" ]]; then
    echo "::error::Hosted-build policy names an unknown package: $package" >&2
    exit 1
  fi
done < <(jq -r 'keys[]' "$policy")

# Evaluate the complete current package set in a foreground command so errors
# cannot disappear through process substitution. Never build a default target.
current=$(nix eval --json --option eval-cores 1 --no-allow-import-from-derivation \
  ".#packages.$TARGET_SYSTEM" --apply 'builtins.mapAttrs (_: package: package.drvPath)')
valid_map='type == "object" and all(.[]; type == "string" and startswith("/nix/store/") and endswith(".drv"))'
jq -e "$valid_map" <<<"$current" >/dev/null

# Optional attribute names narrow the macOS job to its representative outputs.
# All candidates still pass through the same policy filter below.
if [[ $# -gt 0 ]]; then
  for package in "$@"; do
    if ! jq -e --arg package "$package" 'has($package)' <<<"$current" >/dev/null; then
      echo "::error::Unknown native package candidate: $package" >&2
      exit 1
    fi
  done
  candidates=$(printf '%s\n' "$@" | jq -Rsc 'split("\n")[:-1]')
  current=$(jq --argjson candidates "$candidates" \
    'with_entries(select(.key as $name | $candidates | index($name)))' <<<"$current")
fi

base_sha=${BASE_SHA:-}
# Older queue reconcilers do not supply a root CI input. A GitHub queue
# candidate has the previous main as its first parent, including squash queues.
# Use it only for dispatches
# on the checked-out queue SHA; ordinary manual dispatches rebuild everything.
if [[ -z $base_sha && ${GITHUB_EVENT_NAME:-} == workflow_dispatch &&
  ${GITHUB_REF:-} == refs/heads/gh-readonly-queue/main/* &&
  ${GITHUB_SHA:-} == "$(git rev-parse HEAD)" ]]; then
  read -r -a commit_and_parents <<<"$(git rev-list --parents -n 1 HEAD)"
  if [[ ${#commit_and_parents[@]} -ge 2 ]]; then
    base_sha=${commit_and_parents[1]}
  fi
fi

base='{}'
if [[ $base_sha =~ ^[0-9a-f]{40}$ ]] &&
  git cat-file -e "$base_sha^{commit}" 2>/dev/null &&
  git merge-base --is-ancestor "$base_sha" HEAD; then
  # Read the gitlinks at the historical revision, not the current submodule
  # worktrees. Missing submodule history or an invalid base safely rebuilds all.
  if candidate=$(nix eval --json --option eval-cores 1 --no-allow-import-from-derivation \
    --no-write-lock-file "git+file://$PWD?rev=$base_sha&submodules=1#packages.$TARGET_SYSTEM" \
    --apply 'builtins.mapAttrs (_: package: package.drvPath)') &&
    jq -e "$valid_map" <<<"$candidate" >/dev/null; then
    base=$candidate
  else
    echo '::notice::Base package evaluation unavailable; selecting all eligible candidates.' >&2
  fi
else
  echo '::notice::Base history unavailable; selecting all eligible candidates.' >&2
fi

# Keep stdout machine-readable for the workflow. Report exclusions separately.
jq -r --argjson current "$current" '
  to_entries[] | select(.key as $name | $current | has($name)) |
  "::notice::Skipping \(.key): \(.value)"
' "$policy" >&2
jq -n --argjson current "$current" --argjson base "$base" --arg system "$TARGET_SYSTEM" \
  --slurpfile policy "$policy" '
  [$current | to_entries[] | select(.key as $name | $policy[0] | has($name) | not) |
    select(.value != $base[.key]) |
    ".#packages.\($system).\(.key | tojson)"]'
