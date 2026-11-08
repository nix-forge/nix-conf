# shellcheck shell=bash
for media_repair in /run/systemd/system.control/*.service; do
  if [[ -f $media_repair && ! -L $media_repair ]]; then
    IFS= read -r media_repair_header <"$media_repair" || true
    if [[ $media_repair_header == '# desktop-media-mount-repair' ]]; then
      rm -f -- "$media_repair"
    fi
  fi
done
