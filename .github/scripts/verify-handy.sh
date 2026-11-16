#!/usr/bin/env bash
set -euo pipefail

# Native host verification always runs, including when base comparison skipped
# the sandbox check. A matching derivation does not realize its output here.
# The out-link keeps this exact application alive for the entire proof.
printf '::group::Handy package artifact realization\n'
time artifact=$(nix build --out-link "$RUNNER_TEMP/handy-artifact" --print-out-paths \
  .#checks.aarch64-darwin.handy-artifact)
printf '::endgroup::\n'
export HANDY_TEST_BUNDLE="$artifact/Applications/Handy.app"

printf '::group::Handy test shell realization\n'
# Record the realized environment once in Nix's supported profile format.
# Nix activates it with the compatible shell, without re-evaluating this flake
# or asking the runner's system Bash to parse generated shell functions.
time nix print-dev-env .#tests --profile "$RUNNER_TEMP/handy-test-environment" \
  --json >/dev/null
printf '::endgroup::\n'

printf '::group::Handy native identity and signature execution\n'
time nix develop "$RUNNER_TEMP/handy-test-environment" --command \
  python3 "$PWD/tests/macos/test_handy_signature.py"
printf '::endgroup::\n'
