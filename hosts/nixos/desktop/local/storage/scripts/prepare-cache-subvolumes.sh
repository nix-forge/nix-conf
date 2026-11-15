# shellcheck shell=bash
set -euo pipefail
mountpoint -q /srv/data
mountpoint -q /srv/data/work
for directory in /srv/data/cache /srv/data/work/scratch; do
  if [[ ! -e $directory ]]; then btrfs subvolume create "$directory"; fi
  # A normal restored directory is not a snapshot boundary. Refuse it.
  btrfs subvolume show "$directory" >/dev/null
  chown root:root "$directory"
  tag="$directory/CACHEDIR.TAG"
  signature='Signature: 8a477f597d28d172789f06886806bc55'
  if [[ -e $tag || -L $tag ]]; then
    [[ ! -L $tag && -f $tag && $(head -c 43 "$tag") == "$signature" ]]
  else
    printf '%s\n# Regenerable caches and task scratch only.\n' "$signature" >"$tag"
  fi
  chmod 0644 "$tag"
done
chmod 0700 /srv/data/cache
chmod 0755 /srv/data/work/scratch
install -d -m 0700 /srv/data/cache/restic /srv/data/cache/restic/tmp
