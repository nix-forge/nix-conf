# shellcheck shell=bash
if [[ $# != 1 || ! -e $1 && ! -L $1 ]]; then
  echo "Expected one existing Home Manager conflict path" >&2
  exit 1
fi
umask 077
backup_root="${XDG_STATE_HOME:-$HOME/.local/state}/home-manager/conflicts"
mkdir -p -- "$backup_root"
backup_dir=$(mktemp -d "$backup_root/backup.XXXXXXXX")
printf '%s\n' "$1" >"$backup_dir/original-path"
# Dereference file symlinks so garbage collection cannot erase the
# preserved content of a manually installed Nix-store configuration.
if [[ -L $1 && ! -e $1 ]]; then
  printf 'Symlink target was unavailable at backup time.\n' >"$backup_dir/content-unavailable"
else
  cp -aL -- "$1" "$backup_dir/content"
fi
mv -- "$1" "$backup_dir/original"
printf 'Preserved unmanaged configuration in %s\n' "$backup_dir" >&2
