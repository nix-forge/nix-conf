{ myLib, pkgs, ... }: {
  homelab.music.artwork.enable = true;
  homelab.music.lyrics.enable = true;

  # Remove only this task's temporary units after normal NixOS activation.
  system.activationScripts.music-metadata-runtime-cleanup.text =
    myLib.writers.renderBashText { inherit pkgs; }
      {
        name = "music-metadata-runtime-cleanup-text.sh";
        text = ''
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
        '';
      }
      { pkgs_coreutils = pkgs.coreutils; };

  # Retire this desktop's temporary runtime deployment after the declarative
  # units take over. This is a migration for this host, not reusable policy.
  system.activationScripts.music-artwork-runtime-cleanup.text =
    myLib.writers.renderBashText { inherit pkgs; }
      {
        name = "music-artwork-runtime-cleanup-text.sh";
        text = ''
          # shellcheck shell=bash
          for artwork_runtime in /run/systemd/system/music-artwork.{service,timer} /run/systemd/system/aurral.service.d/96-canonical-artwork.conf /run/systemd/system/navidrome.service.d/96-album-track-art.conf /run/systemd/system/music-artwork.service.d/96-untagged-artwork.conf; do
            if [[ -f $artwork_runtime && ! -L $artwork_runtime ]]; then
              IFS= read -r artwork_header <"$artwork_runtime" || true
              if [[ $artwork_header == '# Temporary canonical music artwork deployment.' ]]; then
                @pkgs_coreutils@/bin/rm -- "$artwork_runtime"
              fi
            fi
          done
        '';
      }
      { pkgs_coreutils = pkgs.coreutils; };
}
