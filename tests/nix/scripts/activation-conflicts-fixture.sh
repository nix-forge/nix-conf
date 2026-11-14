# shellcheck shell=bash
# shellcheck disable=SC1090 # The check supplies the actual generated fragment.
set -euo pipefail
run() {
  [[ $1 == fixture-backup && $# == 2 ]] || return 1
  if [[ ${DRY_RUN:-0} != 1 ]]; then
    printf '%s\0' "$2"
  fi
}
source "$1"
