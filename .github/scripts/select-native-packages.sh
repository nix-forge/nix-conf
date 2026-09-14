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

# Project explicit candidates before forcing drvPath. Nix keeps unrelated
# packages lazy, which matters for the representative Darwin build selection.
# JSON encodes arbitrary attribute names; escape Nix interpolation separately.
candidate_literal=$(jq -rn --args '$ARGS.positional | tojson | @json' -- "$@")
candidate_literal=${candidate_literal//\$\{/\\\$\{}
projection="packages: let
  requested = builtins.fromJSON $candidate_literal;
  names = if requested == [] then builtins.attrNames packages else requested;
  project = names: builtins.listToAttrs (map (name: {
    inherit name; value = (builtins.getAttr name packages).drvPath;
  }) names);
in"
# getAttr rejects unknown current candidates; only the historical set may lack
# a newly exported candidate. Keep evaluation failures in foreground commands.
current=$(nix eval --json --option eval-cores 1 --no-allow-import-from-derivation \
  ".#packages.$TARGET_SYSTEM" --apply "$projection project names")
valid_map='type == "object" and all(.[]; type == "string" and startswith("/nix/store/") and endswith(".drv"))'
jq -e "$valid_map" <<<"$current" >/dev/null
# Historical outputs removed from the current set cannot affect build selection.
# Do not force them: a broken retired output must not trigger fallback rebuilds.
current_names=$(jq -r 'keys | tojson | @json' <<<"$current")
current_names=${current_names//\$\{/\\\$\{}

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
    --apply "$projection project (builtins.filter (name: builtins.hasAttr name packages) (builtins.fromJSON $current_names))") &&
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
