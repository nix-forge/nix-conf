# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
set -euo pipefail
export HOME="$TMPDIR/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$gitConfig"
git init practice
git -C practice st >"$TMPDIR/git-status"
test -s "$TMPDIR/git-status"

mkdir -p search/{.git,.direnv,node_modules,src}
touch search/.git/internal search/.direnv/internal search/node_modules/internal
touch search/src/guide.nix search/.visible-hidden
cd search
eval "$searchCommand" >"$TMPDIR/search-results"
grep -Fx 'src/guide.nix' "$TMPDIR/search-results"
grep -Fx '.visible-hidden' "$TMPDIR/search-results"
test "$(wc -l <"$TMPDIR/search-results")" -eq 2
test "$(fzf --filter guide <"$TMPDIR/search-results")" = src/guide.nix
touch "$out"
