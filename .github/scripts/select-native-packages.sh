#!/usr/bin/env bash
set -euo pipefail

# Evaluate the complete current package set in a foreground command so errors
# cannot disappear through process substitution. Never build a default target.
current=$(nix eval --json --option eval-cores 1 --no-allow-import-from-derivation \
  ".#packages.$TARGET_SYSTEM" --apply 'builtins.mapAttrs (_: package: package.drvPath)')
valid_map='type == "object" and all(.[]; type == "string" and startswith("/nix/store/") and endswith(".drv"))'
jq -e "$valid_map" <<<"$current" >/dev/null

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
    echo '::notice::Base package evaluation unavailable; building all current outputs.' >&2
  fi
else
  echo '::notice::Base history unavailable; building all current outputs.' >&2
fi

jq -n --argjson current "$current" --argjson base "$base" --arg system "$TARGET_SYSTEM" '
  [$current | to_entries[] | select(.value != $base[.key]) |
    ".#packages.\($system).\(.key | tojson)"]'
