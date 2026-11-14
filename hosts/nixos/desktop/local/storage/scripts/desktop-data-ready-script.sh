# shellcheck shell=bash
set -eu
@lib_concatMapStringsSep_n_path_mountpoint_q_lib_escapeShellA@
chmod 0700 /srv/data/.snapshots /srv/data/work/.snapshots
# Clear inherited directory NOCOW after a restore. Existing image
# extents need a separate cold copy to regain data checksums.
chattr -C /var/lib/libvirt/images
# Steam checks write access at the library root, not only within
# steamapps. Apply this after the mount checks so a missing data
# drive never makes the fallback directory writable on root.
chown root:users /mnt/games
chmod 2775 /mnt/games
install -d -m 2775 -o root -g users /mnt/games/steamapps /srv/data/work/projects /srv/data/media
