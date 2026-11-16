#!/usr/bin/env bash
set -euo pipefail

case "$DEV_SHELL" in
ciPython | ci) ;;
*)
  echo 'Only reviewed static tool shells can seed this cache' >&2
  exit 2
  ;;
esac
# The profile retains exact tool dependencies through the cache post-action's GC.
# Do not seed application, host, private or redistribution-restricted closures.
nix print-dev-env ".#$DEV_SHELL" --profile "$RUNNER_TEMP/cache-environment" \
  >"$RUNNER_TEMP/cache-environment.sh"
{
  printf '### Retained %s closure\n\n' "$CACHE_SCOPE"
  nix path-info --closure-size "$RUNNER_TEMP/cache-environment"
  echo 'NAR closure size is distinct from compressed cache size.'
  echo 'The cache post-action records the actual save and transfer result.'
} >>"$GITHUB_STEP_SUMMARY"
