#!@bash@
# shellcheck shell=bash
set -euo pipefail
export LC_ALL=C

[ -z "$(@git@ -C . rev-parse --show-prefix 2>/dev/null)" ] || {
  printf 'The preparation source must be the Git checkout root.\n' >&2
  exit 78
}
source_revision="$(@git@ -C . rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || {
  printf 'The Git checkout does not have a known committed revision.\n' >&2
  exit 78
}
case "$source_revision" in "" | *[!0-9a-fA-F]*)
  printf 'The Git revision is not a valid commit identifier.\n' >&2
  exit 78
  ;;
esac
@git@ -C . cat-file -e "$source_revision^{commit}" 2>/dev/null || {
  printf 'The Git revision could not be verified as a commit.\n' >&2
  exit 78
}
source_files_digest="$(@secureFileSystem@ snapshot-tree . | @sha256sum@ | @cut@ -d ' ' -f 1)" || {
  printf 'The source tree could not be snapshotted safely.\n' >&2
  exit 78
}
source_revision_after="$(@git@ -C . rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || {
  printf 'The Git checkout changed while it was being snapshotted.\n' >&2
  exit 78
}
[ "$source_revision" = "$source_revision_after" ] || {
  printf 'The Git checkout changed while it was being snapshotted.\n' >&2
  exit 78
}
printf '%s %s\n' "$source_revision" "$source_files_digest"
