# shellcheck shell=bash
set -eu

media_root=$1
music_folder=$2
media_group=$3
root_owner=$4
root_group=$5
navidrome_owner=$6
navidrome_group=$7
audiomuse_owner=$8
audiomuse_group=$9

discovery_root=$media_root/.services/music-discovery
backup_root=$discovery_root/backups

install_owned_dir() {
  local mode=$1 owner=$2 group=$3 path=$4
  if [ "$(id -u)" -eq 0 ]; then
    install -d -m "$mode" -o "$owner" -g "$group" "$path"
  elif [ "$owner" = "$(id -un)" ] && [ "$group" = "$(id -gn)" ]; then
    # Unprivileged fixture runs can enforce the same modes when ownership
    # already matches. Nix builders cannot set the setgid bit, so the fixture
    # exercises group access; root activation applies the full 2770 mode.
    if [ "$mode" = 2770 ]; then
      install -d -m 0770 "$path"
    else
      install -d -m "$mode" "$path"
    fi
  else
    printf '%s\n' "Cannot set ownership of $path without root" >&2
    return 1
  fi
}

install_owned_dir 2770 "$root_owner" "$media_group" "$music_folder"
# install -d only repairs the final component. A restrictive parent left by an
# older layout would otherwise block both backup users from reaching their dirs.
install_owned_dir 0711 "$root_owner" "$root_group" "$discovery_root"
install_owned_dir 0711 "$root_owner" "$root_group" "$backup_root"
install_owned_dir 0700 "$navidrome_owner" "$navidrome_group" "$backup_root/navidrome"
install_owned_dir 0700 "$audiomuse_owner" "$audiomuse_group" "$backup_root/audiomuse"
