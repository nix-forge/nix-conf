# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
set -euo pipefail
export DRY_RUN=1
run() {
  printf 'DRY-RUN %s\n' "$*"
}
verboseEcho() {
  printf '%s\n' "$*"
}
export -f run verboseEcho

bash @dockActivation@ >"$TMPDIR/output"
grep -F -- '--remove all' "$TMPDIR/output" >/dev/null
grep -F -- '--add /Applications/Missing Test.app' "$TMPDIR/output" >/dev/null
bash @finderActivation@ >"$TMPDIR/finder-output"
grep -F -- 'finder-favorites apply' "$TMPDIR/finder-output" >/dev/null
test -f @finderConfiguration@
test ! -L @finderConfiguration@
grep -F -- '--config @finderConfiguration@' \
  "$TMPDIR/finder-output" >/dev/null
test ! -e /Users/check-user/.cache/home-manager-macos
test ! -e /Users/check-user/.local/state/finder-favorites
touch "$out"
