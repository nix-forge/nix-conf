# shellcheck shell=bash
# nixfmt formats stdin without restricting the source filename's extension.
set -euo pipefail
temporary=$(mktemp)
trap 'rm -f "$temporary"' EXIT
for source in "$@"; do
  # --filename labels stdin; output goes to a distinct temporary file.
  # shellcheck disable=SC2094
  nixfmt --strict --width 100 --filename "$source" <"$source" >"$temporary"
  cat "$temporary" >"$source"
done
