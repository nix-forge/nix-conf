# shellcheck shell=bash
cache_dir=$1
session_root=$2
default_session=$3
shift 3
users=("$@")

mkdir -p -- "$cache_dir"

resolve_session() {
  local name="${1##*/}" directory
  for directory in wayland-sessions xsessions; do
    if [[ -f "$session_root/share/$directory/$name" ]]; then
      printf '%s' "$session_root/share/$directory/$name"
      return 0
    fi
  done
  return 1
}

default_path=$(resolve_session "$default_session")
for user in "${users[@]}"; do
  cache="$cache_dir/lastsession-path-$user"
  # A deliberately saved free-form command takes precedence until the user
  # chooses a desktop entry again.
  if [[ ! -e $cache && -s "$cache_dir/lastsession-$user" ]]; then
    continue
  fi
  selected=""
  if [[ -f $cache && ! -L $cache ]]; then
    selected=$(<"$cache")
  fi
  if ! selected=$(resolve_session "$selected"); then
    selected=$default_path
  fi
  printf '%s' "$selected" >"$cache"
done

# Pre-fill the sole configured account on first use; authentication is still
# required. Preserve a remembered username when there are multiple accounts.
if [[ ! -s "$cache_dir/lastuser" && ${#users[@]} == 1 ]]; then
  printf '%s' "${users[0]}" >"$cache_dir/lastuser"
fi

# Keep remembered selections readable after writing them as the greeter.
shopt -s nullglob
for cache in "$cache_dir"/last*; do
  if [[ -f $cache && ! -L $cache ]]; then
    chmod 0644 -- "$cache"
  fi
done
