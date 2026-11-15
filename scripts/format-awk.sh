# shellcheck shell=bash
# GNU awk's pretty printer parses the program without executing its actions.
temporary=$(mktemp)
trap 'rm -f -- "$temporary"' EXIT
for source in "$@"; do
  gawk --pretty-print="$temporary" --file="$source" </dev/null
  cat "$temporary" >"$source"
done
