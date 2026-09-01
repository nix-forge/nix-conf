#!@bash@
# shellcheck shell=bash
set -euo pipefail
[ "$#" -eq 1 ] || {
  printf 'Exactly one database directory is required.\n' >&2
  exit 64
}
exec @secureFileSystem@ exec-cluster "$1" 18 @pgControldata@ . >/dev/null 2>&1
