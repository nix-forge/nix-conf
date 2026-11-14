# shellcheck shell=bash
for metadata_runtime in /run/systemd/system/music-lyrics.{service,timer} /run/systemd/system/homelab-integrate-{lidarr,jellyfin}.service.d/97-music-metadata.conf; do
  if [[ -f $metadata_runtime && ! -L $metadata_runtime ]]; then
    IFS= read -r metadata_header <"$metadata_runtime" || true
    if [[ $metadata_header == '# Temporary shared music metadata deployment.' ]]; then
      @pkgs_coreutils@/bin/rm -- "$metadata_runtime"
    fi
  fi
done
for metadata_root in music-lyrics.service music-lyrics.timer homelab-integrate-lidarr.service homelab-integrate-jellyfin.service lidarr-scoped; do
  if [[ -L "/nix/var/nix/gcroots/music-metadata-runtime/$metadata_root" ]]; then
    @pkgs_coreutils@/bin/rm -- "/nix/var/nix/gcroots/music-metadata-runtime/$metadata_root"
  fi
done
