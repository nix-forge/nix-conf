# shellcheck shell=bash
for artwork_runtime in /run/systemd/system/music-artwork.{service,timer} /run/systemd/system/aurral.service.d/96-canonical-artwork.conf /run/systemd/system/navidrome.service.d/96-album-track-art.conf /run/systemd/system/music-artwork.service.d/96-untagged-artwork.conf; do
  if [[ -f $artwork_runtime && ! -L $artwork_runtime ]]; then
    IFS= read -r artwork_header <"$artwork_runtime" || true
    if [[ $artwork_header == '# Temporary canonical music artwork deployment.' ]]; then
      @pkgs_coreutils@/bin/rm -- "$artwork_runtime"
    fi
  fi
done
