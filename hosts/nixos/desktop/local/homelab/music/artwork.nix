{ pkgs, ... }: {
  homelab.music.artwork.enable = true;
  homelab.music.lyrics.enable = true;

  # Remove only this task's temporary units after normal NixOS activation.
  system.activationScripts.music-metadata-runtime-cleanup.text =
    (import ../../../../../../lib/templates/text.nix) ./scripts/music-metadata-runtime-cleanup-text.sh
      { pkgs_coreutils = pkgs.coreutils; };

  # Retire this desktop's temporary runtime deployment after the declarative
  # units take over. This is a migration for this host, not reusable policy.
  system.activationScripts.music-artwork-runtime-cleanup.text =
    (import ../../../../../../lib/templates/text.nix) ./scripts/music-artwork-runtime-cleanup-text.sh
      { pkgs_coreutils = pkgs.coreutils; };
}
