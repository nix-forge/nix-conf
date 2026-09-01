#!@bash@
# shellcheck shell=bash
set -euo pipefail
export LC_ALL=C
[ "$#" -eq 1 ] || {
  printf 'Exactly one source directory is required.\n' >&2
  exit 64
}
exec @secureFileSystem@ snapshot-tree "$1"
