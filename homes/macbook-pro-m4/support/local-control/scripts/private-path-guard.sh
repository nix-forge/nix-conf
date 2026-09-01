#!@bash@
# shellcheck shell=bash
set -euo pipefail
[ "$#" -ge 2 ] || {
  printf 'Usage: local-control-private-path MODE PATH [DESCRIPTION] [FILE_MODE]\n' >&2
  exit 64
}
case "$1" in
ensure-directory)
  [ "$#" -ge 3 ] || exit 64
  exec @secureFileSystem@ ensure-directory "$2"
  ;;
validate-directory)
  [ "$#" -ge 3 ] || exit 64
  exec @secureFileSystem@ validate-directory "$2"
  ;;
validate-file)
  [ "$#" -eq 4 ] || exit 64
  exec @secureFileSystem@ validate-file "$2" "$4"
  ;;
*)
  printf 'The private path guard received an invalid mode.\n' >&2
  exit 64
  ;;
esac
