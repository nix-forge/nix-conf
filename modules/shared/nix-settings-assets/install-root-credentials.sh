# shellcheck shell=bash
set -euo pipefail
root_home=$1
source=$2
target="$root_home/.config/nix/nix.conf"
if [[ -e $target || -L $target ]]; then
  previous=$(readlink "$target" || true)
  case "$previous" in
  /nix/store/*-root-nix-credentials.conf) ;;
  "$source") exit 0 ;;
  *)
    echo 'Refusing to replace unmanaged root Nix configuration; preserve and reconcile it first.' >&2
    exit 1
    ;;
  esac
fi
install -d -m 0700 "$root_home/.config/nix"
# Rename a sibling symlink atomically; never overwrite an unmanaged target.
link=$(mktemp "$root_home/.config/nix/.credentials.XXXXXX")
trap 'rm -f "$link"' EXIT
rm "$link"
ln -s "$source" "$link"
mv -f "$link" "$target"
