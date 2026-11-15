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
# Capture the realized shell once. Execution below sources that exact environment
# rather than asking Nix to evaluate or realize the tests shell again.
time nix print-dev-env .#tests >"$RUNNER_TEMP/handy-test-environment.sh"
printf '::endgroup::\n'

printf '::group::Handy native identity and signature execution\n'
time bash -euo pipefail -c 'source "$1"; python3 "$2"' -- \
  "$RUNNER_TEMP/handy-test-environment.sh" "$PWD/tests/macos/test_handy_signature.py"
printf '::endgroup::\n'
