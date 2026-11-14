# shellcheck shell=bash
# Nix supplies the test binary and output path.
# shellcheck disable=SC2154
set -euo pipefail
export GCOV_PREFIX="$TMPDIR/coverage"
export HOME="$TMPDIR/home"
mkdir -p "$GCOV_PREFIX" "$HOME"
"$HYPRLAND_GTESTS" 2>&1 | tee "$out"
grep -Eq '\[[[:space:]]*PASSED[[:space:]]*\][[:space:]]+[1-9][0-9]* tests?' "$out"
if grep -Fq '[  FAILED  ]' "$out"; then
  exit 1
fi
